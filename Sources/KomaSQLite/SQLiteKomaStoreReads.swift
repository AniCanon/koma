import CKomaSQLite
import Foundation
import Koma

public extension SQLiteKomaStore {
    nonisolated func fetch<Record: KomaEntityRecord>(_ request: KomaQueryRequest<Record>) async throws -> [Record] {
        // Reads inside a transaction must observe its uncommitted writes, and stores
        // configured with a custom decoder stay on the legacy writer path; everything else
        // reads from the pool against the last committed WAL snapshot, concurrently with
        // the writer.
        if let readPool, !usesCustomDecoder, SQLiteKomaTransactionContext.id == nil {
            try await ensureSchemaForRead(of: request)
            let usesSQLiteFastPath = usesSQLiteFastPath
            return try await readPool.withConnection { access in
                try Self.executeFetch(request, usesSQLiteFastPath: usesSQLiteFastPath, decoder: nil, access: access)
            }
        }
        return try await fetchOnWriter(request)
    }

    nonisolated func count<Record: KomaEntityRecord>(_ request: KomaQueryRequest<Record>) async throws -> Int {
        if let readPool, SQLiteKomaTransactionContext.id == nil {
            try await ensureSchemaForRead(of: request)
            return try await readPool.withConnection { access in
                try Self.executeCount(request, access: access)
            }
        }
        return try await countOnWriter(request)
    }
}

extension SQLiteKomaStore {
    /// Confirms the request's tables exist before a pooled read; only tables not yet ensured
    /// this session pay the hop to the writer.
    nonisolated func ensureSchemaForRead<Record: KomaEntityRecord>(
        of request: KomaQueryRequest<Record>
    ) async throws {
        if ensuredTables.contains(Record.komaTableName),
           request.joins.allSatisfy({ ensuredTables.contains($0.tableName) })
        {
            return
        }
        try await ensureSchemaOnWriter(request)
    }

    private func ensureSchemaOnWriter<Record: KomaEntityRecord>(
        _ request: KomaQueryRequest<Record>
    ) async throws {
        await waitForTransactionAccess()
        try await ensureSchema(for: Record.self)
        for join in request.joins {
            try ensureSchema(tableName: join.tableName, primaryKey: join.primaryKey, columns: join.columns)
        }
    }

    func fetchOnWriter<Record: KomaEntityRecord>(_ request: KomaQueryRequest<Record>) async throws -> [Record] {
        try await ensureSchemaOnWriter(request)
        return try Self.executeFetch(
            request,
            usesSQLiteFastPath: usesSQLiteFastPath,
            decoder: decoder,
            access: writerAccess
        )
    }

    func countOnWriter<Record: KomaEntityRecord>(_ request: KomaQueryRequest<Record>) async throws -> Int {
        try await ensureSchemaOnWriter(request)
        return try Self.executeCount(request, access: writerAccess)
    }

    static func executeFetch<Record: KomaEntityRecord>(
        _ request: KomaQueryRequest<Record>,
        usesSQLiteFastPath: Bool,
        decoder: JSONDecoder?,
        access: SQLiteDatabaseAccess
    ) throws -> [Record] {
        let fastRecordType = Record.self as? any KomaSQLiteFastPathRecord.Type
        let usesDirectRecordPath = usesSQLiteFastPath && decoder == nil && fastRecordType != nil
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

        return try access.withStatement(sql) { statement in
            for (index, argument) in arguments.enumerated() {
                try Self.bind(argument, to: statement, at: Int32(index + 1))
            }

            if usesDirectRecordPath, let fastRecordType {
                // Open the fast-path existential once for the whole result set; the row loop
                // then makes direct witness calls with no per-row metatype call or `as?` cast.
                // The final array cast is an O(1) identity check because the opened type is
                // dynamically `Record`.
                func decodeRows<FastRecord: KomaSQLiteFastPathRecord>(_: FastRecord.Type) throws -> [Record] {
                    var rows: [FastRecord] = []
                    if let limit = request.limit {
                        rows.reserveCapacity(limit)
                    }
                    let reader = SQLiteStatementRowReader(statement: statement)
                    while true {
                        let step = sqlite3_step(statement)
                        if step == SQLITE_DONE {
                            break
                        }
                        guard step == SQLITE_ROW else {
                            throw SQLiteKomaError.executionFailed("SQLite fetch failed.")
                        }
                        try rows.append(FastRecord.komaSQLiteRecord(from: reader))
                    }
                    guard let records = rows as? [Record] else {
                        throw SQLiteKomaError.executionFailed("SQLite fast path returned an unexpected record type.")
                    }
                    return records
                }
                return try decodeRows(fastRecordType)
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
                if let decoder {
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

    static func executeCount<Record: KomaEntityRecord>(
        _ request: KomaQueryRequest<Record>,
        access: SQLiteDatabaseAccess
    ) throws -> Int {
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

        return try access.withStatement(sql) { statement in
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
