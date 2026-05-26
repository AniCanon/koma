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
            public func komaSQLiteValue(at index: Int) -> KomaSQLiteStorageValue {
                switch index {
                \(raw: properties.enumerated().map { "case \($0.offset): KomaSQLiteStorageValue(self.\($0.element.name))" }
                .joined(separator: "\n        "))
                default: preconditionFailure("Invalid Koma SQLite column index.")
                }
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
        let fusedVariables = properties
            .map { "var \($0.name): \(Self.jsonSQLiteTemporaryType(for: $0)) = nil" }
            .joined(separator: "\n        ")
        let cases = Self.jsonFirstByteCases(for: properties)
        let fusedCases = Self.jsonSQLiteFirstByteCases(for: properties)
        let jsonParameters = properties
            .map { "_komaJSON_\($0.name) \($0.name): \(Self.jsonTemporaryType(for: $0))" }
            .joined(separator: ", ")
        let jsonArguments = properties
            .map { "_komaJSON_\($0.name): \($0.name)" }
            .joined(separator: ", ")
        let jsonAssignments = Self.jsonAssignments(for: properties)
        let encodeFields = properties
            .map { "try writer.writeField(\"\($0.name)\", self.\($0.name), isFirst: &isFirst)" }
            .joined(separator: "\n        ")
        let bindFields = Self.jsonSQLiteBindFields(for: properties)
        let estimatedBytesPerRecord = Self.jsonEstimatedBytesPerRecord(for: properties)

        return [
            """
            public static let komaUsesJSONFastPath = true
            """,
            """
            public static func komaJSONRecords(from data: borrowing Data) throws -> [Self] {
                try KomaJSONRecordDecoder.decodeArray(
                    from: data,
                    estimatedBytesPerRecord: \(raw: estimatedBytesPerRecord)
                ) { scanner in
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

                try scanner.readObjectKeyed { key, scanner in
                    switch key.firstByte {
                    \(raw: cases)
                    default:
                        try scanner.skipValue()
                    }
                }

                return try Self(\(raw: jsonArguments))
            }
            """,
            """
            public static func komaJSONBindRecords<Binder: KomaSQLiteJSONValueBinder>(
                from data: borrowing Data,
                makeBinder: () throws -> Binder,
                finish: (inout Binder) throws -> Void
            ) throws {
                try KomaJSONRecordDecoder.scanArray(from: data) { scanner in
                    \(raw: fusedVariables)

                    try scanner.readObjectKeyed { key, scanner in
                        switch key.firstByte {
                        \(raw: fusedCases)
                        default:
                            try scanner.skipValue()
                        }
                    }

                    var binder = try makeBinder()
                    \(raw: bindFields)
                    try finish(&binder)
                }
            }
            """,
            """
            private init(\(raw: jsonParameters)) throws {
                \(raw: jsonAssignments)
            }
            """,
            """
            public static func komaJSONData(records: borrowing [Self]) throws -> Data {
                try KomaJSONRecordEncoder.encodeArray(
                    records,
                    estimatedBytesPerRecord: \(raw: estimatedBytesPerRecord)
                ) { record, writer in
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

    private static func jsonAssignments(for properties: [EntityProperty]) -> String {
        properties
            .map {
                if $0.isOptional {
                    return "self.\($0.name) = \($0.name)"
                }
                return "self.\($0.name) = try komaJSONRequire(\($0.name), \"\($0.name)\")"
            }
            .joined(separator: "\n        ")
    }

    private static func jsonSQLiteBindFields(for properties: [EntityProperty]) -> String {
        properties
            .map {
                if $0.isOptional {
                    return "try binder.bind(\($0.name))"
                }
                return "try binder.bind(try komaJSONRequire(\($0.name), \"\($0.name)\"))"
            }
            .joined(separator: "\n            ")
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

    private static func jsonSQLiteTemporaryType(for property: EntityProperty) -> String {
        if property.baseType == "String" {
            return "KomaJSONText?"
        }
        return jsonTemporaryType(for: property)
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

    private static func jsonSQLiteDecodeExpression(for property: EntityProperty) -> String {
        if property.baseType == "String" {
            return property.isOptional ? "readOptionalText()" : "readText()"
        }
        return jsonDecodeExpression(for: property)
    }

    private static func jsonEstimatedBytesPerRecord(for properties: [EntityProperty]) -> Int {
        guard !properties.isEmpty else {
            return 2
        }

        let braces = 2
        let commas = max(0, properties.count - 1)
        let fields = properties.reduce(0) { total, property in
            total + property.name.utf8.count + 3 + Self.jsonEstimatedValueBytes(for: property)
        }
        return max(16, braces + commas + fields)
    }

    private static func jsonEstimatedValueBytes(for property: EntityProperty) -> Int {
        switch property.baseType {
        case "String":
            24
        case "Bool":
            5
        case "Int", "Int8", "Int16", "Int32", "Int64":
            20
        case "Float", "Double", "Date":
            24
        default:
            16
        }
    }

    private static func jsonFirstByteCases(for properties: [EntityProperty]) -> String {
        jsonFirstByteCases(for: properties) { property in
            Self.jsonDecodeExpression(for: property)
        }
    }

    private static func jsonSQLiteFirstByteCases(for properties: [EntityProperty]) -> String {
        jsonFirstByteCases(for: properties) { property in
            Self.jsonSQLiteDecodeExpression(for: property)
        }
    }

    private static func jsonFirstByteCases(
        for properties: [EntityProperty],
        decodeExpression: (EntityProperty) -> String
    ) -> String {
        let grouped = Dictionary(grouping: properties) { property in
            property.name.utf8.first ?? 0
        }

        return grouped.keys.sorted().map { firstByte in
            let chain = (grouped[firstByte] ?? [])
                .enumerated()
                .map { index, property in
                    let prefix = index == 0 ? "if" : "else if"
                    let bytes = Array(property.name.utf8)
                    let byteCount = bytes.count
                    let firstByte = bytes.first ?? 0
                    let secondByte = byteCount > 1 ? bytes[1] : 0
                    let lastByte = bytes.last ?? 0
                    return """
                    \(prefix) key.matches("\(property
                        .name)", count: \(byteCount), firstByte: \(firstByte), secondByte: \(secondByte), lastByte: \(lastByte)) {
                                \(property.name) = try scanner.\(decodeExpression(property))
                            }
                    """
                }
                .joined(separator: " ")

            return """
            case \(firstByte):
                        \(chain) else {
                            try scanner.skipValue()
                        }
            """
        }
        .joined(separator: "\n")
    }
}
