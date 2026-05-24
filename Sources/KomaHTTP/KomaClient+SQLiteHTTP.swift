import Foundation
import Koma
import KomaSQLite
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension KomaClient {
    /// Creates a REST-capable Koma client backed by bundled SQLite and `URLSession`.
    static func sqlite(
        database: KomaSQLiteDatabase,
        schema: KomaSchema? = nil,
        baseURL: URL,
        plugins: [any KomaHTTPPlugin] = [],
        session: URLSession = .shared,
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder(),
        jsonOptimization: KomaJSONOptimization = .automatic
    ) async throws -> KomaClient {
        try await KomaClient.sqlite(
            database: database,
            schema: schema,
            baseURL: baseURL,
            transport: URLSessionKomaTransport(session: session),
            plugins: plugins,
            jsonEncoder: jsonEncoder,
            jsonDecoder: jsonDecoder,
            jsonOptimization: jsonOptimization
        )
    }
}
