import Foundation

/// A persisted refresh registration for one concrete request.
///
/// This record stores request identity and refresh policy only. It does not
/// store bearer tokens, cookies, authorization headers, or raw response bodies.
public struct KomaRefreshRegistrationRecord: KomaEntityRecord, Equatable {
    public var id: String
    public var operationName: String
    public var method: String
    public var path: String
    public var query: String
    public var cacheNamespace: String?
    public var policyLifetime: String
    public var staleAfterSeconds: Double
    public var userScope: String?
    public var expiresAt: Date?
    public var lastRegisteredAt: Date
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var lastError: String?

    public struct Columns: Sendable {
        public init() {}
        public let id = KomaColumn<String>("id")
        public let operationName = KomaColumn<String>("operationName")
        public let method = KomaColumn<String>("method")
        public let path = KomaColumn<String>("path")
        public let query = KomaColumn<String>("query")
        public let cacheNamespace = KomaColumn<String?>("cacheNamespace")
        public let policyLifetime = KomaColumn<String>("policyLifetime")
        public let staleAfterSeconds = KomaColumn<Double>("staleAfterSeconds")
        public let userScope = KomaColumn<String?>("userScope")
        public let expiresAt = KomaColumn<Date?>("expiresAt")
        public let lastRegisteredAt = KomaColumn<Date>("lastRegisteredAt")
        public let lastAttemptAt = KomaColumn<Date?>("lastAttemptAt")
        public let lastSuccessAt = KomaColumn<Date?>("lastSuccessAt")
        public let lastError = KomaColumn<String?>("lastError")
    }

    public static let columns = Columns()
    public static let komaTableName = "_koma_refresh_registrations"
    public static let komaPrimaryKey = "id"
    public static let komaColumns: [KomaColumnMetadata] = [
        .init(name: "id", storage: .text, isPrimaryKey: true),
        .init(name: "operationName", storage: .text),
        .init(name: "method", storage: .text),
        .init(name: "path", storage: .text),
        .init(name: "query", storage: .text),
        .init(name: "cacheNamespace", storage: .text),
        .init(name: "policyLifetime", storage: .text),
        .init(name: "staleAfterSeconds", storage: .real),
        .init(name: "userScope", storage: .text),
        .init(name: "expiresAt", storage: .real),
        .init(name: "lastRegisteredAt", storage: .real),
        .init(name: "lastAttemptAt", storage: .real),
        .init(name: "lastSuccessAt", storage: .real),
        .init(name: "lastError", storage: .text)
    ]

    public init(
        id: String,
        operationName: String,
        method: String,
        path: String,
        query: String,
        cacheNamespace: String?,
        policyLifetime: String,
        staleAfterSeconds: Double,
        userScope: String?,
        expiresAt: Date?,
        lastRegisteredAt: Date,
        lastAttemptAt: Date? = nil,
        lastSuccessAt: Date? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.operationName = operationName
        self.method = method
        self.path = path
        self.query = query
        self.cacheNamespace = cacheNamespace
        self.policyLifetime = policyLifetime
        self.staleAfterSeconds = staleAfterSeconds
        self.userScope = userScope
        self.expiresAt = expiresAt
        self.lastRegisteredAt = lastRegisteredAt
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.lastError = lastError
    }

    public var isExpired: Bool {
        expiresAt.map { $0 <= Date() } ?? false
    }

    public func isDue(now: Date = Date()) -> Bool {
        guard expiresAt.map({ $0 > now }) ?? true else {
            return false
        }
        guard let lastSuccessAt else {
            return true
        }
        return now.timeIntervalSince(lastSuccessAt) >= staleAfterSeconds
    }
}
