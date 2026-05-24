import CKomaSQLite
import Foundation

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

    func withStatement<Result>(_ sql: String, _ body: (OpaquePointer) throws -> Result) throws -> Result {
        guard let db = connection.rawValue else {
            throw SQLiteKomaError.closed
        }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteKomaError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        return try body(statement)
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
}
