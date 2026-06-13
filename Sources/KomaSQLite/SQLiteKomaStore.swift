import CKomaSQLite
import Foundation
import Koma

public actor SQLiteKomaStore: KomaStore {
    var connection: SQLiteConnection
    let statementCache = SQLiteStatementCache()
    let path: String
    var encoder: JSONEncoder?
    let decoder: JSONDecoder?
    /// Mirrors `decoder != nil` as a Sendable flag so nonisolated read routing can consult it
    /// without depending on JSONDecoder's sendability on every platform.
    let usesCustomDecoder: Bool
    let usesSQLiteFastPath: Bool
    var canUseFreshSchemaCreation: Bool
    let ensuredTables = SQLiteEnsuredTables()
    /// Read-only WAL connections that serve reads concurrently with this actor's writes.
    /// nil for in-memory databases, where separate connections would see separate stores.
    let readPool: SQLiteReadPool?
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
        usesCustomDecoder = decoder != nil
        self.usesSQLiteFastPath = usesSQLiteFastPath
        canUseFreshSchemaCreation = Self.isKnownFreshDatabase(path)

        // SQLite access is serialized by this actor, so per-connection SQLite mutexes are redundant here.
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        var openedConnection: OpaquePointer?
        guard sqlite3_open_v2(path, &openedConnection, flags, nil) == SQLITE_OK, let connection = openedConnection else {
            let message = openedConnection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unable to open SQLite database."
            if let openedConnection {
                sqlite3_close(openedConnection)
            }
            throw SQLiteKomaError.openFailed(message)
        }
        self.connection = SQLiteConnection(rawValue: connection)
        // Readers open lazily on first use, so the pool costs nothing at startup.
        readPool = path == ":memory:" ? nil : SQLiteReadPool(
            path: path,
            capacity: min(4, max(2, ProcessInfo.processInfo.activeProcessorCount / 2))
        )
        try Self.installVectorFunctions(on: connection)
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
