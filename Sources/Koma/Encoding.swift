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

    public static func bodyData(
        from value: borrowing some KomaEntityRecord & KomaJSONFastPathRecord,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Data {
        try bodyData(from: value, encoder: encoder, optimization: .automatic)
    }

    public static func bodyData(
        from value: borrowing [some KomaEntityRecord & KomaJSONFastPathRecord],
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Data {
        try bodyData(from: value, encoder: encoder, optimization: .automatic)
    }

    public static func bodyData(
        from value: some Encodable,
        encoder: JSONEncoder = JSONEncoder(),
        optimization: KomaJSONOptimization
    ) throws -> Data {
        try bodyData(from: value, encoder: encoder)
    }

    public static func bodyData(
        from value: borrowing some KomaEntityRecord & KomaJSONFastPathRecord,
        encoder: JSONEncoder = JSONEncoder(),
        optimization: KomaJSONOptimization = .automatic
    ) throws -> Data {
        guard optimization == .automatic,
              canUseKomaRecordFastPath(encoder: encoder)
        else {
            return try encoder.encode(value)
        }
        return try value.komaJSONData()
    }

    public static func bodyData<Record: KomaEntityRecord & KomaJSONFastPathRecord>(
        from value: borrowing [Record],
        encoder: JSONEncoder = JSONEncoder(),
        optimization: KomaJSONOptimization = .automatic
    ) throws -> Data {
        guard optimization == .automatic,
              canUseKomaRecordFastPath(encoder: encoder)
        else {
            return try encoder.encode(value)
        }
        return try Record.komaJSONData(records: value)
    }

    private static func stringValue(_ value: Any) -> String {
        switch value {
        case let value as String:
            return value
        case let number as NSNumber:
            // JSONSerialization hands back every JSON number and every JSON boolean as an
            // NSNumber, and an NSNumber matches `as Bool` whatever it holds. Only the boxed
            // boolean may encode as `true` / `false`; an `Int` of 0 or 1 must stay numeric.
            return Self.isBoolean(number) ? (number.boolValue ? "true" : "false") : String(describing: number)
        case let value as Bool:
            return value ? "true" : "false"
        default:
            return String(describing: value)
        }
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        #if canImport(Darwin)
        return CFGetTypeID(number) == CFBooleanGetTypeID()
        #else
        // swift-corelibs-foundation reports a boxed boolean as the ObjC char types.
        // JSON never produces an `Int8`, so no integer is misread as a boolean here.
        let type = number.objCType.pointee
        return type == UInt8(ascii: "c") || type == UInt8(ascii: "B")
        #endif
    }

    private static func canUseKomaRecordFastPath(encoder: JSONEncoder) -> Bool {
        guard encoder.outputFormatting.isEmpty,
              encoder.userInfo.isEmpty
        else {
            return false
        }

        switch encoder.dateEncodingStrategy {
        case .deferredToDate:
            break
        default:
            return false
        }

        switch encoder.dataEncodingStrategy {
        case .base64:
            break
        default:
            return false
        }

        switch encoder.keyEncodingStrategy {
        case .useDefaultKeys:
            break
        default:
            return false
        }

        switch encoder.nonConformingFloatEncodingStrategy {
        case .throw:
            return true
        default:
            return false
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
