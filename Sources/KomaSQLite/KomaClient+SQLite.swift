import Foundation
import Koma

public extension SQLiteKomaStore {
    /// Opens a SQLite-backed Koma store at a resolved database location.
    static func open(
        database: KomaSQLiteDatabase,
        schema: KomaSchema? = nil
    ) async throws -> SQLiteKomaStore {
        let path = try database.resolvedPath()
        if let schema {
            return try await SQLiteKomaStore(path: path, schema: schema)
        }
        return try await SQLiteKomaStore(path: path)
    }
}

public extension KomaClient {
    /// Creates a Koma client backed by bundled SQLite and the provided transport.
    static func sqlite(
        database: KomaSQLiteDatabase,
        schema: KomaSchema? = nil,
        baseURL: URL,
        transport: any KomaTransport,
        plugins: [any KomaHTTPPlugin] = [],
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder(),
        jsonOptimization: KomaJSONOptimization = .automatic
    ) async throws -> KomaClient {
        let store = try await SQLiteKomaStore.open(database: database, schema: schema)
        return KomaClient(
            baseURL: baseURL,
            store: store,
            transport: transport,
            plugins: plugins,
            jsonEncoder: jsonEncoder,
            jsonDecoder: jsonDecoder,
            jsonOptimization: jsonOptimization
        )
    }
}
