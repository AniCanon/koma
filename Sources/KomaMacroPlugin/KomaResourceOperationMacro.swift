import SwiftSyntax

extension KomaResourceMacro {
    static func parameters(from element: EnumCaseElementSyntax) -> [ResourceParameter] {
        let source = element.source
        guard let open = source.firstIndex(of: "("),
              let close = source.lastIndex(of: ")"),
              open < close
        else {
            return []
        }

        let parametersSource = String(source[source.index(after: open) ..< close])
        return Self.splitTopLevel(parametersSource).enumerated().map { index, rawParameter in
            let pieces = rawParameter.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            let declaration = pieces[0]
            let defaultValue = pieces.count > 1 ? pieces[1] : nil

            if let colon = declaration.firstIndex(of: ":") {
                let names = String(declaration[..<colon])
                    .split(whereSeparator: { $0.isWhitespace })
                    .map(String.init)
                let type = String(declaration[declaration.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)

                // `_ name: Type` declares an external label of `_` and a local name of `name`.
                // Only the local name is valid inside the generated body.
                if names.count == 2, names[0] == "_" {
                    return ResourceParameter(
                        label: "_",
                        localName: names[1],
                        type: type,
                        defaultValue: defaultValue,
                        isUnlabeled: true
                    )
                }

                let label = names.first ?? ""
                return ResourceParameter(label: label, localName: label, type: type, defaultValue: defaultValue, isUnlabeled: false)
            }

            let type = declaration.trimmingCharacters(in: .whitespacesAndNewlines)
            let localName = index == 0 ? Self.localName(for: type) : "value\(index)"
            return ResourceParameter(label: "_", localName: localName, type: type, defaultValue: defaultValue, isUnlabeled: true)
        }
    }

    static func clientMethod(for operation: ResourceOperation, basePath: String, recordType: String) -> String {
        """
        public func \(operation.name)(\(signature(for: operation))) -> KomaFetch<\(operation.output), \(recordType)> {
            KomaFetch(
                client: self.koma,
                operation: KomaOperation(
                    name: "\(operation.name)",
                    method: .\(operation.method),
                    path: KomaPath.join("\(basePath)", "\(operation.path)"),
                    queryItems: \(queryItems(for: operation)),
                    pathValues: \(pathValues(for: operation)),
                    body: \(body(for: operation)),\(headersArgument(for: operation))
                    cache: \(operation.cache),
                    adapter: \(operation.adapter),
                    isRefreshable: \(operation.isRefreshable)
                ),
                output: \(operation.output).self,
                record: \(recordType).self
            )
        }
        """
    }

    /// Generates the method for a `returning:` route: a command that decodes the response and
    /// hands it back. No `cache`, `adapter`, or `isRefreshable` — nothing is stored, so there is
    /// no local copy to name, adapt, or keep fresh.
    static func returningClientMethod(for operation: ResourceOperation, basePath: String) -> String {
        """
        public func \(operation.name)(\(signature(for: operation))) -> KomaReturningCommand<\(operation.output)> {
            KomaReturningCommand(
                client: self.koma,
                operation: KomaOperation(
                    name: "\(operation.name)",
                    method: .\(operation.method),
                    path: KomaPath.join("\(basePath)", "\(operation.path)"),
                    queryItems: \(queryItems(for: operation)),
                    pathValues: \(pathValues(for: operation)),
                    body: \(body(for: operation))\(headersArgument(for: operation, isTrailing: true))
                ),
                value: \(operation.output).self
            )
        }
        """
    }

    private static func signature(for operation: ResourceOperation) -> String {
        operation.parameters.map { parameter in
            if parameter.isUnlabeled {
                if let defaultValue = parameter.defaultValue {
                    return "_ \(parameter.localName): \(parameter.type) = \(defaultValue)"
                }
                return "_ \(parameter.localName): \(parameter.type)"
            }
            if let defaultValue = parameter.defaultValue {
                return "\(parameter.label): \(parameter.type) = \(defaultValue)"
            }
            return "\(parameter.label): \(parameter.type)"
        }.joined(separator: ", ")
    }

    /// The `headers:` argument, or an empty string when the route sends no headers of its own.
    ///
    /// A `headers` case parameter is merged over the route's fixed `headers:`, so a call can
    /// add the values only it knows — a multipart boundary — without restating the rest.
    private static func headersArgument(for operation: ResourceOperation, isTrailing: Bool = false) -> String {
        let parameter = operation.parameters.first { $0.localName == "headers" }
        let expression: String
        switch (operation.headers, parameter) {
        case let (.some(fixed), .some(parameter)):
            expression = "\(fixed).merging(\(parameter.localName)) { $1 }"
        case let (.some(fixed), .none):
            expression = fixed
        case let (.none, .some(parameter)):
            expression = parameter.localName
        case (.none, .none):
            return ""
        }
        return isTrailing ? ",\n                    headers: \(expression)" : "\n                    headers: \(expression),"
    }

    private static func pathValues(for operation: ResourceOperation) -> String {
        let placeholders = Self.placeholders(in: operation.path)
        guard !placeholders.isEmpty else {
            return "[:]"
        }
        let entries = placeholders.map { placeholder in
            "\"\(placeholder)\": String(describing: \(placeholder))"
        }
        return "[\(entries.joined(separator: ", "))]"
    }

    private static func queryItems(for operation: ResourceOperation) -> String {
        // A fetch encodes query items on `GET` only; a returning route encodes them whatever
        // its method, because a write's leftover parameters have nowhere else to go.
        guard operation.method == "get" || operation.isReturning else {
            return "[]"
        }

        let pathNames = Set(Self.placeholders(in: operation.path))
        let queryParameters = operation.parameters.filter { parameter in
            parameter.localName != "body"
                && parameter.localName != "headers"
                && !pathNames.contains(parameter.localName)
        }

        if queryParameters.count == 1,
           let parameter = queryParameters.first,
           parameter.isQueryStruct
        {
            return "KomaQueryEncoder.queryItems(from: \(parameter.localName), encoder: self.koma.jsonEncoder)"
        }

        let items = queryParameters.map { parameter in
            "KomaQueryEncoder.queryItem(name: \"\(parameter.queryName)\", value: \(parameter.localName), encoder: self.koma.jsonEncoder)"
        }
        return "[\(items.joined(separator: ", "))].compactMap { $0 }"
    }

    private static func body(for operation: ResourceOperation) -> String {
        guard let bodyParameter = operation.parameters.first(where: { $0.localName == "body" }) else {
            return "nil"
        }

        // A body already in its wire form is sent as written. Only a value that still has to
        // be encoded goes through the JSON encoder — `Data` is `Encodable`, so encoding it
        // would send a base64 string instead of the bytes.
        switch bodyParameter.type.trimmingCharacters(in: .whitespaces) {
        case "KomaRequestBody":
            return bodyParameter.localName
        case "Data", "Foundation.Data":
            return "KomaRequestBody { \(bodyParameter.localName) }"
        default:
            break
        }

        return """
        KomaRequestBody {
            try KomaQueryEncoder.bodyData(
                from: \(bodyParameter.localName),
                encoder: self.koma.jsonEncoder,
                optimization: self.koma.jsonOptimization
            )
        }
        """
    }

    private static func placeholders(in path: String) -> [String] {
        var placeholders: [String] = []
        var searchStart = path.startIndex
        while let open = path[searchStart...].firstIndex(of: "{"),
              let close = path[open...].firstIndex(of: "}")
        {
            placeholders.append(String(path[path.index(after: open) ..< close]))
            searchStart = path.index(after: close)
        }
        return placeholders
    }

    private static func localName(for type: String) -> String {
        if type.hasSuffix("Params") || type.hasSuffix("Parameters") {
            return "params"
        }
        return "value"
    }

    struct ResourceOperation {
        let name: String
        let method: String
        let path: String
        let output: String
        let isReturning: Bool
        let cache: String
        let adapter: String
        let isRefreshable: Bool
        let headers: String?
        let parameters: [ResourceParameter]
    }

    struct ResourceParameter {
        let label: String
        let localName: String
        let type: String
        let defaultValue: String?
        let isUnlabeled: Bool

        var queryName: String {
            isUnlabeled ? localName : label
        }

        var isQueryStruct: Bool {
            isUnlabeled || type.hasSuffix("Params") || type.hasSuffix("Parameters")
        }
    }
}
