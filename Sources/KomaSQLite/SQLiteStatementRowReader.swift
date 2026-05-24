import CKomaSQLite
import Foundation
import Koma

struct SQLiteStatementRowReader: KomaSQLiteRowReader, @unchecked Sendable {
    let statement: OpaquePointer

    func _string(at index: Int) throws -> String {
        guard sqlite3_column_type(statement, Int32(index)) == SQLITE_TEXT,
              let bytes = sqlite3_column_text(statement, Int32(index))
        else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "String")
        }
        return String(cString: bytes)
    }

    func _optionalString(at index: Int) throws -> String? {
        if isNull(index) {
            return nil
        }
        return try _string(at: index)
    }

    func _bool(at index: Int) throws -> Bool {
        guard sqlite3_column_type(statement, Int32(index)) == SQLITE_INTEGER else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "Bool")
        }
        return sqlite3_column_int64(statement, Int32(index)) != 0
    }

    func _optionalBool(at index: Int) throws -> Bool? {
        if isNull(index) {
            return nil
        }
        return try _bool(at: index)
    }

    func _integer<Value: FixedWidthInteger & SignedInteger>(
        at index: Int,
        as type: Value.Type = Value.self
    ) throws -> Value {
        guard sqlite3_column_type(statement, Int32(index)) == SQLITE_INTEGER,
              let converted = Value(exactly: sqlite3_column_int64(statement, Int32(index)))
        else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "\(type)")
        }
        return converted
    }

    func _optionalInteger<Value: FixedWidthInteger & SignedInteger>(
        at index: Int,
        as type: Value.Type = Value.self
    ) throws -> Value? {
        if isNull(index) {
            return nil
        }
        return try _integer(at: index, as: type)
    }

    func _real<Value: BinaryFloatingPoint>(
        at index: Int,
        as type: Value.Type = Value.self
    ) throws -> Value {
        switch sqlite3_column_type(statement, Int32(index)) {
        case SQLITE_FLOAT:
            return Value(sqlite3_column_double(statement, Int32(index)))
        case SQLITE_INTEGER:
            return Value(sqlite3_column_int64(statement, Int32(index)))
        default:
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "\(type)")
        }
    }

    func _optionalReal<Value: BinaryFloatingPoint>(
        at index: Int,
        as type: Value.Type = Value.self
    ) throws -> Value? {
        if isNull(index) {
            return nil
        }
        return try _real(at: index, as: type)
    }

    func _date(at index: Int) throws -> Date {
        try Date(timeIntervalSinceReferenceDate: _real(at: index, as: Double.self))
    }

    func _optionalDate(at index: Int) throws -> Date? {
        try _optionalReal(at: index, as: Double.self).map(Date.init(timeIntervalSinceReferenceDate:))
    }

    func _data(at index: Int) throws -> Data {
        guard sqlite3_column_type(statement, Int32(index)) == SQLITE_BLOB else {
            throw KomaSQLiteFastPathError.typeMismatch(index: index, expected: "Data")
        }
        let count = Int(sqlite3_column_bytes(statement, Int32(index)))
        guard let bytes = sqlite3_column_blob(statement, Int32(index)), count > 0 else {
            return Data()
        }
        return Data(bytes: bytes, count: count)
    }

    func _optionalData(at index: Int) throws -> Data? {
        if isNull(index) {
            return nil
        }
        return try _data(at: index)
    }

    private func isNull(_ index: Int) -> Bool {
        sqlite3_column_type(statement, Int32(index)) == SQLITE_NULL
    }
}
