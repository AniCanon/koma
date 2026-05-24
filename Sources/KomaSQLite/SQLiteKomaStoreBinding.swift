import CKomaSQLite
import Foundation
import Koma

extension SQLiteKomaStore {
    static func bind(_ value: Any, to statement: OpaquePointer, at index: Int32) throws {
        var binder = SQLiteStatementBinder(statement: statement, index: index)
        if value is NSNull {
            try binder.bindNull()
            return
        }

        switch value {
        case let value as String:
            try binder.bind(value)
        case let value as Bool:
            try binder.bind(value)
        case let value as Int:
            try binder.bind(value)
        case let value as Int64:
            try binder.bind(value)
        case let value as Double:
            try binder.bind(value)
        case let value as NSNumber:
            try binder.bind(value.doubleValue)
        case let value as Data:
            try binder.bind(value)
        default:
            try binder.bind(String(describing: value))
        }
    }

    static func bind(_ value: borrowing KomaValue, to statement: OpaquePointer, at index: Int32) throws {
        var binder = SQLiteStatementBinder(statement: statement, index: index)
        switch value {
        case let .string(value):
            try binder.bind(value)
        case let .int(value):
            try binder.bind(value)
        case let .double(value):
            try binder.bind(value)
        case let .bool(value):
            try binder.bind(value)
        }
    }

    static func bind(_ value: borrowing KomaSQLiteStorageValue, to statement: OpaquePointer, at index: Int32) throws {
        var binder = SQLiteStatementBinder(statement: statement, index: index)
        try binder.bind(value)
    }
}
