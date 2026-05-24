import CKomaSQLite
import Foundation

struct SQLiteDecodedRow {
    private let values: [String: SQLiteColumnValue]

    init(statement: OpaquePointer, columns: [String]) {
        var values: [String: SQLiteColumnValue] = [:]
        values.reserveCapacity(columns.count)

        for (offset, column) in columns.enumerated() {
            let index = Int32(offset)
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                values[column] = .integer(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                values[column] = .real(sqlite3_column_double(statement, index))
            case SQLITE_TEXT:
                values[column] = .text(sqlite3_column_text(statement, index).map { String(cString: $0) } ?? "")
            case SQLITE_BLOB:
                let count = Int(sqlite3_column_bytes(statement, index))
                if let bytes = sqlite3_column_blob(statement, index), count > 0 {
                    values[column] = .blob(Data(bytes: bytes, count: count))
                } else {
                    values[column] = .blob(Data())
                }
            case SQLITE_NULL:
                values[column] = .null
            default:
                values[column] = .null
            }
        }

        self.values = values
    }

    var allColumnNames: [String] {
        Array(values.keys)
    }

    func value(for column: String) -> SQLiteColumnValue? {
        values[column]
    }
}

enum SQLiteColumnValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
}

struct SQLiteRowDecoder: Decoder {
    let row: SQLiteDecodedRow
    var codingPath: [any CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        try Value(from: self)
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        KeyedDecodingContainer(SQLiteKeyedDecodingContainer<Key>(row: row, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch(
            [Any].self,
            DecodingError.Context(codingPath: codingPath, debugDescription: "SQLite rows do not support unkeyed decoding.")
        )
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        throw DecodingError.typeMismatch(
            Any.self,
            DecodingError.Context(codingPath: codingPath, debugDescription: "SQLite rows require keyed decoding.")
        )
    }
}

struct SQLiteKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let row: SQLiteDecodedRow
    let codingPath: [any CodingKey]

    var allKeys: [Key] {
        row.allColumnNames.compactMap(Key.init(stringValue:))
    }

    func contains(_ key: Key) -> Bool {
        row.value(for: key.stringValue) != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        try value(for: key) == .null
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: String.Type, forKey key: Key) throws -> String {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decode<Value: Decodable>(_ type: Value.Type, forKey key: Key) throws -> Value {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key]).decode(type)
    }

    func decodeIfPresent<Value: Decodable>(_ type: Value.Type, forKey key: Key) throws -> Value? {
        guard let value = row.value(for: key.stringValue), value != .null else {
            return nil
        }
        return try SQLiteValueDecoder(value: value, codingPath: codingPath + [key]).decode(type)
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        throw DecodingError.typeMismatch(
            [String: Any].self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "SQLite columns do not support nested keyed values."
            )
        )
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch(
            [Any].self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "SQLite columns do not support nested unkeyed values."
            )
        )
    }

    func superDecoder() throws -> any Decoder {
        SQLiteValueDecoder(value: .null, codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        try SQLiteValueDecoder(value: value(for: key), codingPath: codingPath + [key])
    }

    private func value(for key: Key) throws -> SQLiteColumnValue {
        guard let value = row.value(for: key.stringValue) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Column '\(key.stringValue)' was not selected.")
            )
        }
        return value
    }
}
