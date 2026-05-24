import CKomaSQLite
import Foundation
import Koma

public extension SQLiteKomaStore {
    func fetch<Record: KomaEntityRecord>(_ request: KomaQueryRequest<Record>) async throws -> [Record] {
        await waitForTransactionAccess()
        try await ensureSchema(for: Record.self)
        for join in request.joins {
            try ensureSchema(tableName: join.tableName, primaryKey: join.primaryKey, columns: join.columns)
        }

        let usesDirectRecordPath = usesSQLiteFastPath && decoder == nil && Record._komaSQLiteFastPath
        let columnMetadata = Record.komaColumns
        let columns = usesDirectRecordPath ? [] : Self.columnNames(from: columnMetadata)
        var arguments: [KomaValue] = []
        var sql = Self.selectSQL(tableName: Record.komaTableName, columns: columnMetadata, joins: request.joins)

        if let predicate = request.predicate {
            let qualifier = request.joins.isEmpty ? nil : Record.komaTableName
            let rendered = try Self.render(predicate, defaultQualifier: qualifier)
            sql += " WHERE \(rendered.sql)"
            arguments.append(contentsOf: rendered.arguments)
        }

        if !request.order.isEmpty {
            let qualifier = request.joins.isEmpty ? nil : Record.komaTableName
            let order = Self.orderClause(request.order, defaultQualifier: qualifier)
            sql += " ORDER BY \(order)"
        }

        if let limit = request.limit {
            sql += " LIMIT \(limit)"
        }
        if let offset = request.offset {
            if request.limit == nil {
                sql += " LIMIT -1"
            }
            sql += " OFFSET \(offset)"
        }

        return try withStatement(sql) { statement in
            for (index, argument) in arguments.enumerated() {
                try Self.bind(argument, to: statement, at: Int32(index + 1))
            }

            var records: [Record] = []
            if let limit = request.limit {
                records.reserveCapacity(limit)
            }

            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE {
                    break
                }
                guard step == SQLITE_ROW else {
                    throw SQLiteKomaError.executionFailed("SQLite fetch failed.")
                }
                if usesDirectRecordPath {
                    let row = SQLiteStatementRowReader(statement: statement)
                    try records.append(Record._komaSQLiteRecord(from: row))
                } else if let decoder = self.decoder {
                    let object = Self.rowObject(statement: statement, columns: columns)
                    let data = try JSONSerialization.data(withJSONObject: object)
                    try records.append(decoder.decode(Record.self, from: data))
                } else {
                    let row = SQLiteDecodedRow(statement: statement, columns: columns)
                    try records.append(SQLiteRowDecoder(row: row).decode(Record.self))
                }
            }
            return records
        }
    }

    func count<Record: KomaEntityRecord>(_ request: KomaQueryRequest<Record>) async throws -> Int {
        await waitForTransactionAccess()
        try await ensureSchema(for: Record.self)
        for join in request.joins {
            try ensureSchema(tableName: join.tableName, primaryKey: join.primaryKey, columns: join.columns)
        }

        var arguments: [KomaValue] = []
        var sql = Self.countSQL(
            tableName: Record.komaTableName,
            primaryKey: Record.komaPrimaryKey,
            joins: request.joins
        )
        if let predicate = request.predicate {
            let qualifier = request.joins.isEmpty ? nil : Record.komaTableName
            let rendered = try Self.render(predicate, defaultQualifier: qualifier)
            sql += " WHERE \(rendered.sql)"
            arguments.append(contentsOf: rendered.arguments)
        }

        return try withStatement(sql) { statement in
            for (index, argument) in arguments.enumerated() {
                try Self.bind(argument, to: statement, at: Int32(index + 1))
            }
            guard sqlite3_step(statement) == SQLITE_ROW else {
                throw SQLiteKomaError.executionFailed("SQLite count failed.")
            }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }
}
