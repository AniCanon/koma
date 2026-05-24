import Foundation

@_documentation(visibility: private)
public enum KomaQueryEncoder {
    public static func queryItems(
        from value: some Encodable,
        encoder: JSONEncoder = JSONEncoder()
    ) -> [URLQueryItem] {
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return []
        }

        return object
            .compactMap { key, value -> URLQueryItem? in
                if value is NSNull {
                    return nil
                }
                return URLQueryItem(name: key, value: Self.stringValue(value))
            }
            .sorted { $0.name < $1.name }
    }

    public static func queryItem(
        name: String,
        value: some Encodable,
        encoder: JSONEncoder = JSONEncoder()
    ) -> URLQueryItem? {
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              !(object is NSNull)
        else {
            return nil
        }
        return URLQueryItem(name: name, value: Self.stringValue(object))
    }

    public static func bodyData(
        from value: some Encodable,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Data {
        try encoder.encode(value)
    }

    public static func bodyDataIfPossible(
        from value: some Encodable,
        encoder: JSONEncoder = JSONEncoder()
    ) -> Data? {
        try? bodyData(from: value, encoder: encoder)
    }

    private static func stringValue(_ value: Any) -> String {
        switch value {
        case let value as String:
            return value
        case let value as Bool:
            return value ? "true" : "false"
        default:
            return String(describing: value)
        }
    }
}

@_documentation(visibility: private)
public enum KomaPath {
    public static func join(_ basePath: String, _ path: String) -> String {
        let cleanBase = basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if cleanBase.isEmpty {
            return cleanPath
        }
        if cleanPath.isEmpty {
            return cleanBase
        }
        return "\(cleanBase)/\(cleanPath)"
    }

    public static func percentEncodedPathValue(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
