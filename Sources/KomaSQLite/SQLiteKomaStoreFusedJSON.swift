import CKomaSQLite
import Foundation
import Koma

public extension SQLiteKomaStore {
    /// Internal fast path used by resource refreshes to persist JSON arrays without first materializing records.
    @_documentation(visibility: private)
    func upsertJSON<Record: KomaFusedJSONRecord>(_ data: Data, record: Record.Type) async throws {
        await waitForTransactionAccess()
        guard !data.isEmpty else {
            return
        }

        try await ensureSchema(for: Record.self)

        let columns = Record.komaColumns
        let sql = Self.upsertSQL(tableName: Record.komaTableName, primaryKey: Record.komaPrimaryKey, columns: columns)

        let ownsTransaction = !isInsideCurrentTransaction
        if ownsTransaction {
            try execute("BEGIN IMMEDIATE TRANSACTION")
        }
        let changesBefore = totalChanges
        do {
            try withStatement(sql) { statement in
                try Record.komaJSONBindRecords(
                    from: data,
                    makeBinder: {
                        SQLiteStatementBinder(statement: statement)
                    },
                    finish: { binder in
                        guard binder.boundCount == columns.count else {
                            throw SQLiteKomaError.executionFailed("SQLite value count mismatch.")
                        }
                        guard sqlite3_step(statement) == SQLITE_DONE else {
                            throw SQLiteKomaError.executionFailed("SQLite upsert failed.")
                        }
                        sqlite3_reset(statement)
                    }
                )
            }
            if ownsTransaction {
                try execute("COMMIT")
            }
            if totalChanges > changesBefore {
                recordChangedTable(Record.komaTableName)
            }
        } catch {
            if ownsTransaction {
                try? execute("ROLLBACK")
            }
            throw error
        }
    }
}

extension SQLiteKomaStore: KomaFusedJSONStore {}
