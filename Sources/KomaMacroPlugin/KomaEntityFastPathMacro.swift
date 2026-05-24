import SwiftSyntax

extension KomaEntityMacro {
    static func sqliteFastPathMembers(for properties: [EntityProperty]) -> [DeclSyntax] {
        let values = properties
            .map { "_KomaSQLiteValue(self.\($0.name))" }
            .joined(separator: ",\n            ")
        let assignments = properties.enumerated()
            .map { index, property in
                "self.\(property.name) = \(Self.sqliteDecodeExpression(for: property, at: index))"
            }
            .joined(separator: "\n            ")

        return [
            """
            public static let _komaSQLiteFastPath = true
            """,
            """
            public var _komaSQLiteValues: [_KomaSQLiteValue] {
                [
                    \(raw: values)
                ]
            }
            """,
            """
            public func _komaSQLiteValues(into values: inout [_KomaSQLiteValue]) {
                values.reserveCapacity(\(raw: properties.count))
                \(raw: properties.map { "values.append(_KomaSQLiteValue(self.\($0.name)))" }.joined(separator: "\n        "))
            }
            """,
            """
            public func _komaSQLiteBind<Binder: _KomaSQLiteValueBinder>(into binder: inout Binder) throws {
                \(raw: properties.map { "try binder.bind(self.\($0.name))" }.joined(separator: "\n        "))
            }
            """,
            """
            public init<Reader: _KomaSQLiteRowReader>(_komaSQLiteRow row: borrowing Reader) throws {
                \(raw: assignments)
            }
            """,
            """
            public static func _komaSQLiteRecord(from row: _KomaSQLiteRow) throws -> Self {
                try Self(_komaSQLiteRow: row)
            }
            """,
            """
            public static func _komaSQLiteRecord<Reader: _KomaSQLiteRowReader>(from reader: borrowing Reader) throws -> Self {
                try Self(_komaSQLiteRow: reader)
            }
            """
        ]
    }

    static func jsonFastPathMembers(for properties: [EntityProperty]) -> [DeclSyntax] {
        let variables = properties
            .map { "var \($0.name): \(Self.jsonTemporaryType(for: $0)) = nil" }
            .joined(separator: "\n        ")
        let cases = properties
            .map {
                """
                case "\($0.name)":
                            \($0.name) = try scanner.\(Self.jsonDecodeExpression(for: $0))
                """
            }
            .joined(separator: "\n            ")
        let jsonParameters = properties
            .map { "_komaJSON_\($0.name) \($0.name): \(Self.jsonTemporaryType(for: $0))" }
            .joined(separator: ", ")
        let jsonArguments = properties
            .map { "_komaJSON_\($0.name): \($0.name)" }
            .joined(separator: ", ")
        let jsonAssignments = properties
            .map {
                if $0.isOptional {
                    return "self.\($0.name) = \($0.name)"
                }
                return "self.\($0.name) = try _komaJSONRequire(\($0.name), \"\($0.name)\")"
            }
            .joined(separator: "\n        ")
        let encodeFields = properties
            .map { "try writer.writeField(\"\($0.name)\", self.\($0.name), isFirst: &isFirst)" }
            .joined(separator: "\n        ")

        return [
            """
            public static let _komaJSONFastPath = true
            """,
            """
            public static func _komaJSONRecords(from data: borrowing Data) throws -> [Self] {
                try _KomaJSONDecoder.decodeArray(from: data) { scanner in
                    try Self._komaJSONRecord(from: &scanner)
                }
            }
            """,
            """
            public static func _komaJSONRecord(from data: borrowing Data) throws -> Self {
                try _KomaJSONDecoder.decodeObject(from: data) { scanner in
                    try Self._komaJSONRecord(from: &scanner)
                }
            }
            """,
            """
            private static func _komaJSONRecord(from scanner: inout _KomaJSONScanner) throws -> Self {
                \(raw: variables)

                try scanner.readObject { key, scanner in
                    switch key {
                    \(raw: cases)
                    default:
                        try scanner.skipValue()
                    }
                }

                return try Self(\(raw: jsonArguments))
            }
            """,
            """
            private init(\(raw: jsonParameters)) throws {
                \(raw: jsonAssignments)
            }
            """,
            """
            public static func _komaJSONData(records: borrowing [Self]) throws -> Data {
                try _KomaJSONEncoder.encodeArray(records) { record, writer in
                    try record._komaJSONWrite(to: &writer)
                }
            }
            """,
            """
            public func _komaJSONData() throws -> Data {
                try _KomaJSONEncoder.encodeObject(self) { record, writer in
                    try record._komaJSONWrite(to: &writer)
                }
            }
            """,
            """
            public func _komaJSONWrite(to writer: inout _KomaJSONWriter) throws {
                writer.beginObject()
                var isFirst = true
                \(raw: encodeFields)
                writer.endObject()
            }
            """
        ]
    }

    private static func sqliteDecodeExpression(for property: EntityProperty, at index: Int) -> String {
        let optional = property.isOptional
        let type = property.unwrappedType
        let baseType = property.baseType

        switch baseType {
        case "String":
            return optional ? "try row._optionalString(at: \(index))" : "try row._string(at: \(index))"
        case "Bool":
            return optional ? "try row._optionalBool(at: \(index))" : "try row._bool(at: \(index))"
        case "Int", "Int8", "Int16", "Int32", "Int64":
            return optional ? "try row._optionalInteger(at: \(index), as: \(type).self)" : "try row._integer(at: \(index), as: \(type).self)"
        case "Float", "Double":
            return optional ? "try row._optionalReal(at: \(index), as: \(type).self)" : "try row._real(at: \(index), as: \(type).self)"
        case "Date":
            return optional ? "try row._optionalDate(at: \(index))" : "try row._date(at: \(index))"
        case "Data":
            return optional ? "try row._optionalData(at: \(index))" : "try row._data(at: \(index))"
        default:
            return "try row._string(at: \(index))"
        }
    }

    private static func jsonTemporaryType(for property: EntityProperty) -> String {
        property.isOptional ? property.type : "\(property.type)?"
    }

    private static func jsonDecodeExpression(for property: EntityProperty) -> String {
        let optional = property.isOptional
        let type = property.unwrappedType
        let baseType = property.baseType

        switch baseType {
        case "String":
            return optional ? "readOptionalString()" : "readString()"
        case "Bool":
            return optional ? "readOptionalBool()" : "readBool()"
        case "Int", "Int8", "Int16", "Int32", "Int64":
            return optional ? "readOptionalInteger(as: \(type).self)" : "readInteger(as: \(type).self)"
        case "Float":
            return optional ? "readOptionalFloat()" : "readFloat()"
        case "Double":
            return optional ? "readOptionalDouble()" : "readDouble()"
        case "Date":
            return optional ? "readOptionalDate()" : "readDate()"
        default:
            return "skipValue()"
        }
    }
}
