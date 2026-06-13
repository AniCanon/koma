import Foundation

/// A persisted HTTP cache validator (`ETag` / `Last-Modified`) for one concrete GET request.
///
/// Stored validators let refreshes send `If-None-Match` / `If-Modified-Since`; a `304 Not
/// Modified` answer then skips the response download, the decode, and the upsert entirely —
/// the local store is already current. The record stores validator strings only, never
/// response bodies or credentials.
public struct KomaHTTPValidatorRecord: KomaEntityRecord, Equatable {
    public var id: String
    public var operationName: String
    public var etag: String?
    public var lastModified: String?
    public var updatedAt: Date

    public struct Columns: Sendable {
        public init() {}
        public let id = KomaColumn<String>("id")
        public let operationName = KomaColumn<String>("operationName")
        public let etag = KomaColumn<String?>("etag")
        public let lastModified = KomaColumn<String?>("lastModified")
        public let updatedAt = KomaColumn<Date>("updatedAt")
    }

    public static let columns = Columns()
    public static let komaTableName = "_koma_http_validators"
    public static let komaPrimaryKey = "id"
    public static let komaColumns: [KomaColumnMetadata] = [
        .init(name: "id", storage: .text, isPrimaryKey: true),
        .init(name: "operationName", storage: .text),
        .init(name: "etag", storage: .text),
        .init(name: "lastModified", storage: .text),
        .init(name: "updatedAt", storage: .real)
    ]

    public init(
        id: String,
        operationName: String,
        etag: String?,
        lastModified: String?,
        updatedAt: Date
    ) {
        self.id = id
        self.operationName = operationName
        self.etag = etag
        self.lastModified = lastModified
        self.updatedAt = updatedAt
    }
}
