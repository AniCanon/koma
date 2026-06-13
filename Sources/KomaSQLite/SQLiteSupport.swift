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
/// No-op destructor: SQLite reads the caller's bytes in place and never frees them. Only safe
/// when the buffer provably outlives every step of the statement it is bound to.
let SQLITE_STATIC: sqlite3_destructor_type? = nil

struct SQLiteConnection: @unchecked Sendable {
    var rawValue: OpaquePointer?
}

struct SQLiteStatementBinder: KomaSQLiteJSONValueBinder {
    let statement: OpaquePointer
    var index: Int32 = 1

    var boundCount: Int {
        Int(index - 1)
    }

    mutating func bindNull() throws {
        try advance(sqlite3_bind_null(statement, index))
    }

    mutating func bind(_ value: borrowing String) throws {
        if let result = value.utf8.withContiguousStorageIfAvailable({ bytes in
            bindText(bytes, SQLITE_TRANSIENT)
        }) {
            try advance(result)
            return
        }

        let bytes = Array(value.utf8)
        try advance(bytes.withUnsafeBufferPointer { bindText($0, SQLITE_TRANSIENT) })
    }

    mutating func bind(_ value: borrowing KomaJSONText) throws {
        // Buffer-backed text points into the JSON input buffer, which outlives the whole
        // statement loop on the fused path — SQLite can read it at step time without the
        // defensive copy SQLITE_TRANSIENT would make. Escape-materialized strings are only
        // pinned inside the closure, so they keep the copying destructor.
        let destructor = value.isBufferBacked ? SQLITE_STATIC : SQLITE_TRANSIENT
        let result = value.withUnsafeUTF8 { bytes in
            bindText(bytes, destructor)
        }
        try advance(result)
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

    private func bindText(_ bytes: UnsafeBufferPointer<UInt8>, _ destructor: sqlite3_destructor_type?) -> Int32 {
        guard let baseAddress = bytes.baseAddress else {
            return sqlite3_bind_text(statement, index, "", 0, SQLITE_TRANSIENT)
        }
        return baseAddress.withMemoryRebound(to: CChar.self, capacity: bytes.count) { pointer in
            sqlite3_bind_text(statement, index, pointer, Int32(bytes.count), destructor)
        }
    }
}
