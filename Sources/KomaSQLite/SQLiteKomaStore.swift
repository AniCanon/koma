import CKomaSQLite
import Foundation
import Koma

public actor SQLiteKomaStore: KomaStore {
    var connection: SQLiteConnection
    let path: String
    let encoder: JSONEncoder
    let decoder: JSONDecoder?
    let usesSQLiteFastPath: Bool
    var ensuredTables: Set<String> = []
    var activeTransactionID: UUID?
    var transactionWaiters: [CheckedContinuation<Void, Never>] = []

    public init(path: String) async throws {
        try await self.init(path: path, schema: nil, encoder: JSONEncoder(), customDecoder: nil, usesSQLiteFastPath: true)
    }

    public init(path: String, schema: KomaSchema) async throws {
        try await self.init(path: path, schema: schema, encoder: JSONEncoder(), customDecoder: nil, usesSQLiteFastPath: true)
    }

    public init(path: String, decoder: JSONDecoder) async throws {
        try await self.init(path: path, schema: nil, encoder: JSONEncoder(), customDecoder: decoder, usesSQLiteFastPath: true)
    }

    public init(path: String, schema: KomaSchema, decoder: JSONDecoder) async throws {
        try await self.init(path: path, schema: schema, encoder: JSONEncoder(), customDecoder: decoder, usesSQLiteFastPath: true)
    }

    public init(path: String, encoder: JSONEncoder, decoder: JSONDecoder = JSONDecoder()) async throws {
        try await self.init(path: path, schema: nil, encoder: encoder, customDecoder: decoder, usesSQLiteFastPath: false)
    }

    public init(path: String, schema: KomaSchema, encoder: JSONEncoder, decoder: JSONDecoder = JSONDecoder()) async throws {
        try await self.init(path: path, schema: schema, encoder: encoder, customDecoder: decoder, usesSQLiteFastPath: false)
    }

    private init(
        path: String,
        schema: KomaSchema?,
        encoder: JSONEncoder,
        customDecoder decoder: JSONDecoder?,
        usesSQLiteFastPath: Bool
    ) async throws {
        self.path = path
        self.encoder = encoder
        self.decoder = decoder
        self.usesSQLiteFastPath = usesSQLiteFastPath

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        var connection: OpaquePointer?
        guard sqlite3_open_v2(path, &connection, flags, nil) == SQLITE_OK else {
            let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unable to open SQLite database."
            if let connection {
                sqlite3_close(connection)
            }
            throw SQLiteKomaError.openFailed(message)
        }
        self.connection = SQLiteConnection(rawValue: connection)
        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")

        if let schema {
            try applyMigrationPacks(schema.migrationPacks)
            for entity in schema.entities {
                try ensureSchema(
                    tableName: entity.komaTableName,
                    primaryKey: entity.komaPrimaryKey,
                    columns: entity.komaColumns
                )
            }
            try applyLatestSchemaArtifacts(schema.migrationPacks)
        }
    }

    deinit {
        if let db = self.connection.rawValue {
            sqlite3_close(db)
        }
    }

    public func ensureSchema<Record: KomaEntityRecord>(for record: Record.Type) async throws {
        await waitForTransactionAccess()
        try ensureSchema(
            tableName: Record.komaTableName,
            primaryKey: Record.komaPrimaryKey,
            columns: Record.komaColumns
        )
    }
}
