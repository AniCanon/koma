import SwiftSyntax

extension KomaEntityMacro {
    static func sqliteFastPathMembers(for properties: [EntityProperty]) -> [DeclSyntax] {
        let values = properties
            .map { "KomaSQLiteStorageValue(self.\($0.name))" }
            .joined(separator: ",\n            ")
        let assignments = properties.enumerated()
            .map { index, property in
                "self.\(property.name) = \(Self.sqliteDecodeExpression(for: property, at: index))"
            }
            .joined(separator: "\n            ")

        return [
            """
            public static let komaUsesSQLiteFastPath = true
            """,
            """
            public var komaSQLiteValues: [KomaSQLiteStorageValue] {
                [
                    \(raw: values)
                ]
            }
            """,
            """
            public func komaSQLiteValues(into values: inout [KomaSQLiteStorageValue]) {
                values.reserveCapacity(\(raw: properties.count))
                \(raw: properties.map { "values.append(KomaSQLiteStorageValue(self.\($0.name)))" }.joined(separator: "\n        "))
            }
            """,
            """
            public func komaSQLiteBind<Binder: KomaSQLiteValueBinder>(into binder: inout Binder) throws {
                \(raw: properties.map { "try binder.bind(self.\($0.name))" }.joined(separator: "\n        "))
            }
            """,
            """
            public init<Reader: KomaSQLiteRowReader>(komaSQLiteRow row: borrowing Reader) throws {
                \(raw: assignments)
            }
            """,
            """
            public static func komaSQLiteRecord(from row: KomaSQLiteRow) throws -> Self {
                try Self(komaSQLiteRow: row)
            }
            """,
            """
            public static func komaSQLiteRecord<Reader: KomaSQLiteRowReader>(from reader: borrowing Reader) throws -> Self {
                try Self(komaSQLiteRow: reader)
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
                return "self.\($0.name) = try komaJSONRequire(\($0.name), \"\($0.name)\")"
            }
            .joined(separator: "\n        ")
        let encodeFields = properties
            .map { "try writer.writeField(\"\($0.name)\", self.\($0.name), isFirst: &isFirst)" }
            .joined(separator: "\n        ")

        return [
            """
            public static let komaUsesJSONFastPath = true
            """,
            """
            public static func komaJSONRecordValues(from data: borrowing Data) throws -> [any KomaEntityRecord] {
                try komaJSONRecords(from: data)
            }
            """,
            """
            public static func komaJSONRecordValue(from data: borrowing Data) throws -> any KomaEntityRecord {
                try komaJSONRecord(from: data)
            }
            """,
            """
            public static func komaJSONRecords(from data: borrowing Data) throws -> [Self] {
                try KomaJSONRecordDecoder.decodeArray(from: data) { scanner in
                    try Self.komaJSONRecord(from: &scanner)
                }
            }
            """,
            """
            public static func komaJSONRecord(from data: borrowing Data) throws -> Self {
                try KomaJSONRecordDecoder.decodeObject(from: data) { scanner in
                    try Self.komaJSONRecord(from: &scanner)
                }
            }
            """,
            """
            private static func komaJSONRecord(from scanner: inout KomaJSONScanner) throws -> Self {
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
            public static func komaJSONData(records: borrowing [Self]) throws -> Data {
                try KomaJSONRecordEncoder.encodeArray(records) { record, writer in
                    try record.komaJSONWrite(to: &writer)
                }
            }
            """,
            """
            public func komaJSONData() throws -> Data {
                try KomaJSONRecordEncoder.encodeObject(self) { record, writer in
                    try record.komaJSONWrite(to: &writer)
                }
            }
            """,
            """
            public func komaJSONWrite(to writer: inout KomaJSONWriter) throws {
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
