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
                let label = String(declaration[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                let type = String(declaration[declaration.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                return ResourceParameter(label: label, localName: label, type: type, defaultValue: defaultValue, isUnlabeled: false)
            }

            let type = declaration.trimmingCharacters(in: .whitespacesAndNewlines)
            let localName = index == 0 ? Self.localName(for: type) : "value\(index)"
            return ResourceParameter(label: "_", localName: localName, type: type, defaultValue: defaultValue, isUnlabeled: true)
        }
    }

    static func clientMethod(for operation: ResourceOperation, basePath: String, recordType: String) -> String {
        let signature = operation.parameters.map { parameter in
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

        let pathValues = Self.pathValues(for: operation)
        let queryItems = Self.queryItems(for: operation)
        let body = Self.body(for: operation)

        return """
        public func \(operation.name)(\(signature)) -> KomaFetch<\(operation.output), \(recordType)> {
            KomaFetch(
                client: self.koma,
                operation: KomaOperation(
                    name: "\(operation.name)",
                    method: .\(operation.method),
                    path: KomaPath.join("\(basePath)", "\(operation.path)"),
                    queryItems: \(queryItems),
                    pathValues: \(pathValues),
                    body: \(body),
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
        guard operation.method == "get" else {
            return "[]"
        }

        let pathNames = Set(Self.placeholders(in: operation.path))
        let queryParameters = operation.parameters.filter { parameter in
            parameter.label != "body" && !pathNames.contains(parameter.localName)
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
        guard let bodyParameter = operation.parameters.first(where: { $0.label == "body" }) else {
            return "nil"
        }
        return "KomaQueryEncoder.bodyDataIfPossible(from: \(bodyParameter.localName), encoder: self.koma.jsonEncoder)"
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
        let cache: String
        let adapter: String
        let isRefreshable: Bool
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
