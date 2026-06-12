import CKomaSQLite
import Foundation
import Koma

public actor SQLiteKomaStore: KomaStore {
    var connection: SQLiteConnection
    let statementCache = SQLiteStatementCache()
    let path: String
    var encoder: JSONEncoder?
    let decoder: JSONDecoder?
    let usesSQLiteFastPath: Bool
    var canUseFreshSchemaCreation: Bool
    var ensuredTables: Set<String> = []
    var activeTransactionID: UUID?
    var transactionWaiters: [CheckedContinuation<Void, Never>] = []
    var observations: [UUID: SQLiteKomaStoreObservation] = [:]
    var observationIDsByTable: [String: Set<UUID>] = [:]
    var pendingChangedTables: Set<String> = []

    public init(path: String) async throws {
        try await self.init(path: path, schema: nil, encoder: nil, customDecoder: nil, usesSQLiteFastPath: true)
    }

    public init(path: String, schema: KomaSchema) async throws {
        try await self.init(path: path, schema: schema, encoder: nil, customDecoder: nil, usesSQLiteFastPath: true)
    }

    public init(path: String, decoder: JSONDecoder) async throws {
        try await self.init(path: path, schema: nil, encoder: nil, customDecoder: decoder, usesSQLiteFastPath: true)
    }

    public init(path: String, schema: KomaSchema, decoder: JSONDecoder) async throws {
        try await self.init(path: path, schema: schema, encoder: nil, customDecoder: decoder, usesSQLiteFastPath: true)
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
        encoder: JSONEncoder?,
        customDecoder decoder: JSONDecoder?,
        usesSQLiteFastPath: Bool
    ) async throws {
        self.path = path
        self.encoder = encoder
        self.decoder = decoder
        self.usesSQLiteFastPath = usesSQLiteFastPath
        canUseFreshSchemaCreation = Self.isKnownFreshDatabase(path)

        // SQLite access is serialized by this actor, so per-connection SQLite mutexes are redundant here.
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        var connection: OpaquePointer?
        guard sqlite3_open_v2(path, &connection, flags, nil) == SQLITE_OK else {
            let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unable to open SQLite database."
            if let connection {
                sqlite3_close(connection)
            }
            throw SQLiteKomaError.openFailed(message)
        }
        self.connection = SQLiteConnection(rawValue: connection)
        try installVectorFunctions()
        try execute("PRAGMA journal_mode = WAL")
        // NORMAL skips the per-commit WAL fsync (durability moves to checkpoints); on device
        // flash this is the difference between microsecond and millisecond single-row commits.
        // Apps that need FULL can opt back in with rawExecute("PRAGMA synchronous = FULL").
        try execute("PRAGMA synchronous = NORMAL")
        try execute("PRAGMA busy_timeout = 5000")
        try execute("PRAGMA foreign_keys = ON")

        if let schema {
            try applyMigrationPacks(schema.migrationPacks)
            try ensureSchema(for: schema.entities)
            try applyLatestSchemaArtifacts(schema.migrationPacks)
        }
    }

    deinit {
        // close_v2 defers the close until the statement cache's own deinit finalizes the
        // cached statements (actor deinit cannot touch the non-Sendable cache directly).
        if let db = self.connection.rawValue {
            sqlite3_close_v2(db)
        }
    }

    public func ensureSchema<Record: KomaEntityRecord>(for record: Record.Type) async throws {
        await waitForTransactionAccess()
        try ensureSchema(
            tableName: Record.komaTableName,
            primaryKey: Record.komaPrimaryKey,
            columns: Record.komaColumns,
            generatedSQL: (Record.self as? any KomaGeneratedSchemaRecord.Type)?.komaGeneratedCreateTableSQL
        )
    }

    private static func isKnownFreshDatabase(_ path: String) -> Bool {
        guard path != ":memory:" else {
            return true
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: path) else {
            return true
        }

        guard let size = try? fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber else {
            return false
        }
        return size.int64Value == 0
    }
}
