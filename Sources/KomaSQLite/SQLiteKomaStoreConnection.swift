import CKomaSQLite
import Foundation

/// One connection plus its statement cache — the unit both the writer actor and checked-out
/// pool readers execute SQL against. Not Sendable by design: it is confined to whichever
/// executor owns the underlying connection for the duration of the call.
struct SQLiteDatabaseAccess {
    let database: OpaquePointer
    let statementCache: SQLiteStatementCache

    func withStatement<Result>(_ sql: String, _ body: (OpaquePointer) throws -> Result) throws -> Result {
        let statement: OpaquePointer
        if let cached = statementCache.checkout(sql) {
            statement = cached
        } else {
            var prepared: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &prepared, nil) == SQLITE_OK, let prepared else {
                throw SQLiteKomaError.executionFailed(String(cString: sqlite3_errmsg(database)))
            }
            statement = prepared
        }
        defer { statementCache.checkin(sql, statement) }

        return try body(statement)
    }
}

extension SQLiteKomaStore {
    func execute(_ sql: String) throws {
        guard let db = connection.rawValue else {
            throw SQLiteKomaError.closed
        }

        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? "SQLite execution failed."
            sqlite3_free(error)
            throw SQLiteKomaError.executionFailed(message)
        }
    }

    /// The writer connection's access. Actor-isolated; pooled reads use their own connection.
    var writerAccess: SQLiteDatabaseAccess {
        get throws {
            guard let db = connection.rawValue else {
                throw SQLiteKomaError.closed
            }
            return SQLiteDatabaseAccess(database: db, statementCache: statementCache)
        }
    }

    func withStatement<Result>(_ sql: String, _ body: (OpaquePointer) throws -> Result) throws -> Result {
        try writerAccess.withStatement(sql, body)
    }

    func object(from record: some Encodable) throws -> [String: Any] {
        let encoder: JSONEncoder
        if let existingEncoder = self.encoder {
            encoder = existingEncoder
        } else {
            encoder = JSONEncoder()
            self.encoder = encoder
        }

        let data = try encoder.encode(record)
        return try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    var changeCount: Int {
        Int(sqlite3_changes(connection.rawValue))
    }

    /// Lifetime INSERT/UPDATE/DELETE count for the connection; deltas across a batch reveal
    /// whether any row actually changed (change-guarded upserts keep identical rows out).
    var totalChanges: Int {
        Int(sqlite3_total_changes64(connection.rawValue))
    }

    static func quote(_ identifier: String) -> String {
        var sql = ""
        sql.reserveCapacity(identifier.utf8.count + 2)
        Self.appendQuotedIdentifier(identifier, to: &sql)
        return sql
    }

    static func appendQuotedIdentifier(_ identifier: String, to sql: inout String) {
        sql.append("\"")
        guard identifier.contains("\"") else {
            sql.append(identifier)
            sql.append("\"")
            return
        }

        for character in identifier {
            if character == "\"" {
                sql.append("\"\"")
            } else {
                sql.append(character)
            }
        }
        sql.append("\"")
    }

    static func stringLiteral(_ value: String) -> String {
        var sql = "'"
        for character in value {
            if character == "'" {
                sql.append("''")
            } else {
                sql.append(character)
            }
        }
        sql.append("'")
        return sql
    }
}
