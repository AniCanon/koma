import CKomaSQLite
import Foundation
import Koma

public extension SQLiteKomaStore {
    /// Runs an arbitrary `SELECT` with positional (`?`) arguments and returns the result rows.
    nonisolated func rawQuery(_ sql: String, arguments: [KomaSQLiteStorageValue] = []) async throws -> [KomaRawRow] {
        if let readPool, SQLiteKomaTransactionContext.id == nil {
            return try await readPool.withConnection { access in
                try Self.rawRows(sql, arguments: arguments, access: access)
            }
        }
        return try await rawQueryOnWriter(sql, arguments: arguments)
    }

    /// Runs an arbitrary `SELECT` and decodes each row into `Record`.
    ///
    /// The selected columns must be in the record's declared column order (its `komaColumns`);
    /// `SELECT <explicit columns>` or `SELECT t.*` from the record's own table both satisfy this.
    nonisolated func rawQuery<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        _ sql: String,
        arguments: [KomaSQLiteStorageValue] = []
    ) async throws -> [Record] {
        if let readPool, SQLiteKomaTransactionContext.id == nil {
            return try await readPool.withConnection { access in
                try Self.rawRecords(type, sql, arguments: arguments, access: access)
            }
        }
        return try await rawQueryOnWriter(type, sql, arguments: arguments)
    }

    /// Runs a non-`SELECT` statement (INSERT/UPDATE/DELETE, FTS commands, ...) with positional
    /// (`?`) arguments and returns the number of rows changed.
    ///
    /// Pass `invalidating` when the statement mutates tables observed by Koma live queries. Koma
    /// intentionally does not parse arbitrary SQL to infer affected tables.
    @discardableResult
    func rawExecute(
        _ sql: String,
        arguments: [KomaSQLiteStorageValue] = [],
        invalidating tables: Set<String> = []
    ) async throws -> Int {
        await waitForTransactionAccess()
        let changes = try rawExecuteUnchecked(sql, arguments: arguments)
        if !tables.isEmpty {
            recordChangedTables(tables)
        }
        return changes
    }
}

extension SQLiteKomaStore {
    func rawQueryOnWriter(_ sql: String, arguments: [KomaSQLiteStorageValue]) async throws -> [KomaRawRow] {
        await waitForTransactionAccess()
        return try Self.rawRows(sql, arguments: arguments, access: writerAccess)
    }

    func rawQueryOnWriter<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        _ sql: String,
        arguments: [KomaSQLiteStorageValue]
    ) async throws -> [Record] {
        await waitForTransactionAccess()
        return try Self.rawRecords(type, sql, arguments: arguments, access: writerAccess)
    }

    static func rawRows(
        _ sql: String,
        arguments: [KomaSQLiteStorageValue] = [],
        access: SQLiteDatabaseAccess
    ) throws -> [KomaRawRow] {
        try access.withStatement(sql) { statement in
            try Self.bind(arguments, to: statement)
            let columnCount = Int(sqlite3_column_count(statement))

            var columnIndex: [String: Int] = [:]
            columnIndex.reserveCapacity(columnCount)
            for offset in 0 ..< columnCount {
                let name = sqlite3_column_name(statement, Int32(offset)).map { String(cString: $0) } ?? "\(offset)"
                columnIndex[name] = offset
            }

            var rows: [KomaRawRow] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    let values = Self.columnValues(statement: statement, columnCount: columnCount)
                    rows.append(KomaRawRow(values: values, columnIndex: columnIndex))
                case SQLITE_DONE:
                    return rows
                default:
                    throw Self.stepError(statement)
                }
            }
        }
    }

    static func rawRecords<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        _ sql: String,
        arguments: [KomaSQLiteStorageValue] = [],
        access: SQLiteDatabaseAccess
    ) throws -> [Record] {
        try access.withStatement(sql) { statement in
            try Self.bind(arguments, to: statement)
            // Read columns straight off the statement — the same direct path fetch() uses —
            // instead of boxing every column into a KomaSQLiteRow value array per row.
            let reader = SQLiteStatementRowReader(statement: statement)
            var records: [Record] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    try records.append(Record.komaSQLiteRecord(from: reader))
                case SQLITE_DONE:
                    return records
                default:
                    throw Self.stepError(statement)
                }
            }
        }
    }

    @discardableResult
    func rawExecuteUnchecked(_ sql: String, arguments: [KomaSQLiteStorageValue] = []) throws -> Int {
        try withStatement(sql) { statement in
            try Self.bind(arguments, to: statement)
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    continue
                case SQLITE_DONE:
                    return Int(sqlite3_changes(sqlite3_db_handle(statement)))
                default:
                    throw Self.stepError(statement)
                }
            }
        }
    }

    static func bind(_ arguments: [KomaSQLiteStorageValue], to statement: OpaquePointer) throws {
        guard !arguments.isEmpty else { return }
        var binder = SQLiteStatementBinder(statement: statement)
        for argument in arguments {
            switch argument {
            case .null: try binder.bindNull()
            case let .integer(value): try binder.bind(value)
            case let .real(value): try binder.bind(value)
            case let .text(value): try binder.bind(value)
            case let .blob(value): try binder.bind(value)
            }
        }
    }

    static func columnValues(statement: OpaquePointer, columnCount: Int) -> [KomaSQLiteStorageValue] {
        var values: [KomaSQLiteStorageValue] = []
        values.reserveCapacity(columnCount)
        for offset in 0 ..< columnCount {
            let index = Int32(offset)
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                values.append(.integer(sqlite3_column_int64(statement, index)))
            case SQLITE_FLOAT:
                values.append(.real(sqlite3_column_double(statement, index)))
            case SQLITE_TEXT:
                values.append(.text(sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""))
            case SQLITE_BLOB:
                let count = Int(sqlite3_column_bytes(statement, index))
                if let bytes = sqlite3_column_blob(statement, index), count > 0 {
                    values.append(.blob(Data(bytes: bytes, count: count)))
                } else {
                    values.append(.blob(Data()))
                }
            default:
                values.append(.null)
            }
        }
        return values
    }

    static func stepError(_ statement: OpaquePointer) -> SQLiteKomaError {
        let message = sqlite3_db_handle(statement)
            .flatMap(sqlite3_errmsg)
            .map { String(cString: $0) } ?? "SQLite step failed."
        return .executionFailed(message)
    }
}
