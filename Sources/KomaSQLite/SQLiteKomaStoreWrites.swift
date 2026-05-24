import CKomaSQLite
import Foundation
import Koma

public extension SQLiteKomaStore {
    func upsert<Record: KomaEntityRecord>(_ records: [Record]) async throws {
        await waitForTransactionAccess()
        guard !records.isEmpty else {
            return
        }

        try await ensureSchema(for: Record.self)

        let columns = Record.komaColumns
        let sql = Self.upsertSQL(tableName: Record.komaTableName, primaryKey: Record.komaPrimaryKey, columns: columns)

        let ownsTransaction = !isInsideCurrentTransaction
        if ownsTransaction {
            try execute("BEGIN IMMEDIATE TRANSACTION")
        }
        do {
            try withStatement(sql) { statement in
                for record in records {
                    if self.usesSQLiteFastPath, Record._komaSQLiteFastPath {
                        var binder = SQLiteStatementBinder(statement: statement)
                        try record._komaSQLiteBind(into: &binder)
                        guard binder.boundCount == columns.count else {
                            throw SQLiteKomaError.executionFailed("SQLite value count mismatch.")
                        }
                    } else {
                        let object = try self.object(from: record)
                        for (index, column) in columns.enumerated() {
                            try Self.bind(object[column.name] ?? NSNull(), to: statement, at: Int32(index + 1))
                        }
                    }
                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw SQLiteKomaError.executionFailed("SQLite upsert failed.")
                    }
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                }
            }
            if ownsTransaction {
                try execute("COMMIT")
            }
        } catch {
            if ownsTransaction {
                try? execute("ROLLBACK")
            }
            throw error
        }
    }

    func delete<Record: KomaEntityRecord>(_ request: KomaDeleteRequest<Record>) async throws -> Int {
        await waitForTransactionAccess()
        try await ensureSchema(for: Record.self)

        var arguments: [KomaValue] = []
        var sql = "DELETE FROM \(Self.quote(Record.komaTableName))"
        if let predicate = request.predicate {
            let rendered = try Self.render(predicate)
            sql += " WHERE \(rendered.sql)"
            arguments.append(contentsOf: rendered.arguments)
        }

        let ownsTransaction = !isInsideCurrentTransaction
        if ownsTransaction {
            try execute("BEGIN IMMEDIATE TRANSACTION")
        }
        do {
            let changes = try withStatement(sql) { statement in
                for (index, argument) in arguments.enumerated() {
                    try Self.bind(argument, to: statement, at: Int32(index + 1))
                }
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw SQLiteKomaError.executionFailed("SQLite delete failed.")
                }
                return self.changeCount
            }
            if ownsTransaction {
                try execute("COMMIT")
            }
            return changes
        } catch {
            if ownsTransaction {
                try? execute("ROLLBACK")
            }
            throw error
        }
    }

    func update<Record: KomaEntityRecord>(_ request: KomaUpdateRequest<Record>) async throws -> Int {
        await waitForTransactionAccess()
        try await ensureSchema(for: Record.self)
        guard !request.assignments.isEmpty else {
            return 0
        }

        let assignments = Self.updateAssignments(request.assignments)
        var arguments = request.assignments.map(\.value)
        var sql = "UPDATE \(Self.quote(Record.komaTableName)) SET \(assignments)"
        if let predicate = request.predicate {
            let rendered = try Self.render(predicate)
            sql += " WHERE \(rendered.sql)"
            arguments.append(contentsOf: rendered.arguments.map(Optional.some))
        }

        let ownsTransaction = !isInsideCurrentTransaction
        if ownsTransaction {
            try execute("BEGIN IMMEDIATE TRANSACTION")
        }
        do {
            let changes = try withStatement(sql) { statement in
                for (index, argument) in arguments.enumerated() {
                    if let argument {
                        try Self.bind(argument, to: statement, at: Int32(index + 1))
                    } else {
                        try Self.bind(NSNull(), to: statement, at: Int32(index + 1))
                    }
                }
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw SQLiteKomaError.executionFailed("SQLite update failed.")
                }
                return self.changeCount
            }
            if ownsTransaction {
                try execute("COMMIT")
            }
            return changes
        } catch {
            if ownsTransaction {
                try? execute("ROLLBACK")
            }
            throw error
        }
    }

    func transaction<Value: Sendable>(
        _ body: @Sendable (any KomaStore) async throws -> Value
    ) async throws -> Value {
        await waitForTransactionAccess()

        if isInsideCurrentTransaction {
            return try await body(self)
        }

        let transactionID = try beginTransactionScope()
        do {
            let value = try await SQLiteKomaTransactionContext.$id.withValue(transactionID) {
                try await body(self)
            }
            try execute("COMMIT")
            endTransactionScope()
            return value
        } catch {
            try? execute("ROLLBACK")
            ensuredTables.removeAll(keepingCapacity: true)
            endTransactionScope()
            throw error
        }
    }
}
