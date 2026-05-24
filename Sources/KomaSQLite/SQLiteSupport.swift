import CKomaSQLite
import Foundation
import Koma

extension KomaStorageKind {
    var sqliteType: String {
        switch self {
        case .text:
            return "TEXT"
        case .integer:
            return "INTEGER"
        case .real:
            return "REAL"
        case .blob:
            return "BLOB"
        }
    }
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SQLiteConnection: @unchecked Sendable {
    var rawValue: OpaquePointer?
}

struct SQLiteStatementBinder: KomaSQLiteValueBinder {
    let statement: OpaquePointer
    var index: Int32 = 1

    var boundCount: Int {
        Int(index - 1)
    }

    mutating func bindNull() throws {
        try advance(sqlite3_bind_null(statement, index))
    }

    mutating func bind(_ value: borrowing String) throws {
        try advance(sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT))
    }

    mutating func bind(_ value: Bool) throws {
        try bind(value ? Int64(1) : Int64(0))
    }

    mutating func bind(_ value: some FixedWidthInteger & SignedInteger) throws {
        try advance(sqlite3_bind_int64(statement, index, Int64(value)))
    }

    mutating func bind(_ value: Float) throws {
        try bind(Double(value))
    }

    mutating func bind(_ value: Double) throws {
        try advance(sqlite3_bind_double(statement, index, value))
    }

    mutating func bind(_ value: Date) throws {
        try bind(value.timeIntervalSinceReferenceDate)
    }

    mutating func bind(_ value: borrowing Data) throws {
        let result = value.withUnsafeBytes { buffer in
            sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
        }
        try advance(result)
    }

    private mutating func advance(_ result: Int32) throws {
        guard result == SQLITE_OK else {
            let message = sqlite3_db_handle(statement)
                .flatMap(sqlite3_errmsg)
                .map { String(cString: $0) } ?? "SQLite bind failed."
            throw SQLiteKomaError.executionFailed(message)
        }
        index += 1
    }
}
