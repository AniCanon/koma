import Foundation

@_documentation(visibility: private)
public protocol KomaSQLiteRowReader: Sendable {
    func _string(at index: Int) throws -> String
    func _optionalString(at index: Int) throws -> String?
    func _bool(at index: Int) throws -> Bool
    func _optionalBool(at index: Int) throws -> Bool?
    func _integer<Value: FixedWidthInteger & SignedInteger>(at index: Int, as type: Value.Type) throws -> Value
    func _optionalInteger<Value: FixedWidthInteger & SignedInteger>(at index: Int, as type: Value.Type) throws -> Value?
    func _real<Value: BinaryFloatingPoint>(at index: Int, as type: Value.Type) throws -> Value
    func _optionalReal<Value: BinaryFloatingPoint>(at index: Int, as type: Value.Type) throws -> Value?
    func _date(at index: Int) throws -> Date
    func _optionalDate(at index: Int) throws -> Date?
    func _data(at index: Int) throws -> Data
    func _optionalData(at index: Int) throws -> Data?
}

@_documentation(visibility: private)
public struct KomaSQLiteRow: KomaSQLiteRowReader, Sendable {
    private let values: [KomaSQLiteStorageValue]

    public init(values: [KomaSQLiteStorageValue]) {
        self.values = values
    }

    public func _string(at index: Int) throws -> String {
        guard case let .text(value) = try value(at: index) else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "String")
        }
        return value
    }

    public func _optionalString(at index: Int) throws -> String? {
        let value = try value(at: index)
        guard value != .null else {
            return nil
        }
        guard case let .text(text) = value else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "String?")
        }
        return text
    }

    public func _bool(at index: Int) throws -> Bool {
        guard case let .integer(value) = try value(at: index) else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "Bool")
        }
        return value != 0
    }

    public func _optionalBool(at index: Int) throws -> Bool? {
        let value = try value(at: index)
        guard value != .null else {
            return nil
        }
        guard case let .integer(integer) = value else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "Bool?")
        }
        return integer != 0
    }

    public func _integer<Value: FixedWidthInteger & SignedInteger>(
        at index: Int,
        as type: Value.Type = Value.self
    ) throws -> Value {
        guard case let .integer(value) = try value(at: index),
              let converted = Value(exactly: value)
        else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "\(type)")
        }
        return converted
    }

    public func _optionalInteger<Value: FixedWidthInteger & SignedInteger>(
        at index: Int,
        as type: Value.Type = Value.self
    ) throws -> Value? {
        let value = try value(at: index)
        guard value != .null else {
            return nil
        }
        guard case let .integer(integer) = value,
              let converted = Value(exactly: integer)
        else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "\(type)?")
        }
        return converted
    }

    public func _real<Value: BinaryFloatingPoint>(
        at index: Int,
        as type: Value.Type = Value.self
    ) throws -> Value {
        switch try value(at: index) {
        case let .real(value):
            return Value(value)
        case let .integer(value):
            return Value(value)
        default:
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "\(type)")
        }
    }

    public func _optionalReal<Value: BinaryFloatingPoint>(
        at index: Int,
        as type: Value.Type = Value.self
    ) throws -> Value? {
        let value = try value(at: index)
        guard value != .null else {
            return nil
        }
        switch value {
        case let .real(real):
            return Value(real)
        case let .integer(integer):
            return Value(integer)
        default:
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "\(type)?")
        }
    }

    public func _date(at index: Int) throws -> Date {
        try Date(timeIntervalSinceReferenceDate: _real(at: index, as: Double.self))
    }

    public func _optionalDate(at index: Int) throws -> Date? {
        try _optionalReal(at: index, as: Double.self).map(Date.init(timeIntervalSinceReferenceDate:))
    }

    public func _data(at index: Int) throws -> Data {
        guard case let .blob(value) = try value(at: index) else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "Data")
        }
        return value
    }

    public func _optionalData(at index: Int) throws -> Data? {
        let value = try value(at: index)
        guard value != .null else {
            return nil
        }
        guard case let .blob(data) = value else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "Data?")
        }
        return data
    }

    private func value(at index: Int) throws -> KomaSQLiteStorageValue {
        guard values.indices.contains(index) else {
            throw KomaSQLiteFastPathError.missingColumn(index)
        }
        return values[index]
    }
}
