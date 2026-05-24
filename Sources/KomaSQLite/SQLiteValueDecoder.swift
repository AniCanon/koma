import Foundation

struct SQLiteValueDecoder: Decoder, SingleValueDecodingContainer {
    let value: SQLiteColumnValue
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] = [:]

    func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        if type == Data.self {
            guard let data = try decodeData() as? Value else {
                throw typeMismatch(type)
            }
            return data
        }
        return try Value(from: self)
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        throw typeMismatch(type)
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        throw typeMismatch([Any].self)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        self
    }

    func decodeNil() -> Bool {
        value == .null
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        switch value {
        case let .integer(value):
            return value != 0
        case let .text(value):
            if value == "true" || value == "1" {
                return true
            }
            if value == "false" || value == "0" {
                return false
            }
            throw typeMismatch(type)
        default:
            throw typeMismatch(type)
        }
    }

    func decode(_ type: String.Type) throws -> String {
        guard case let .text(value) = value else {
            throw typeMismatch(type)
        }
        return value
    }

    func decode(_ type: Double.Type) throws -> Double {
        switch value {
        case let .real(value):
            return value
        case let .integer(value):
            return Double(value)
        default:
            throw typeMismatch(type)
        }
    }

    func decode(_ type: Float.Type) throws -> Float {
        try Float(decode(Double.self))
    }

    func decode(_ type: Int.Type) throws -> Int {
        try integer(type)
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        try integer(type)
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        try integer(type)
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        try integer(type)
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        try integer(type)
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        try unsignedInteger(type)
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        try unsignedInteger(type)
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        try unsignedInteger(type)
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        try unsignedInteger(type)
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        try unsignedInteger(type)
    }

    private func integer<Value: FixedWidthInteger & SignedInteger>(_ type: Value.Type) throws -> Value {
        guard case let .integer(value) = value,
              let converted = Value(exactly: value)
        else {
            throw typeMismatch(type)
        }
        return converted
    }

    private func unsignedInteger<Value: FixedWidthInteger & UnsignedInteger>(_ type: Value.Type) throws -> Value {
        guard case let .integer(value) = value,
              let converted = Value(exactly: value)
        else {
            throw typeMismatch(type)
        }
        return converted
    }

    private func decodeData() throws -> Data {
        switch value {
        case let .blob(value):
            return value
        case let .text(value):
            guard let data = Data(base64Encoded: value) else {
                throw typeMismatch(Data.self)
            }
            return data
        default:
            throw typeMismatch(Data.self)
        }
    }

    private func typeMismatch(_ type: Any.Type) -> DecodingError {
        DecodingError.typeMismatch(
            type,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot decode \(type) from SQLite value \(value).")
        )
    }
}
