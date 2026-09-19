import Foundation

@_documentation(visibility: private)
public struct KomaOperation: Sendable {
    public let name: String
    public let method: KomaHTTPMethod
    public let path: String
    public let queryItems: [URLQueryItem]
    public let pathValues: [String: String]
    public let body: KomaRequestBody?

    /// Headers sent with this operation's request, for fetches and commands alike.
    ///
    /// They override Koma's defaults (`Accept`, and `Content-Type` for a bodied request) —
    /// this is how an operation sends a body Koma does not encode, such as multipart form
    /// data. The client's plugins run last and win over both, so an operation cannot strip
    /// the `Authorization` header a plugin sets or otherwise opt out of the pipeline. Header
    /// names are matched exactly.
    public let headers: [String: String]
    public let cache: KomaCacheDescriptor?
    public let adapter: (any KomaAnyPersistenceAdapter.Type)?
    public let isRefreshable: Bool

    public init(
        name: String,
        method: KomaHTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        pathValues: [String: String] = [:],
        body: KomaRequestBody? = nil,
        headers: [String: String] = [:],
        cache: KomaCacheDescriptor? = nil,
        adapter: (any KomaAnyPersistenceAdapter.Type)? = nil,
        isRefreshable: Bool = false
    ) {
        self.name = name
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.pathValues = pathValues
        self.body = body
        self.headers = headers
        self.cache = cache
        self.adapter = adapter
        self.isRefreshable = isRefreshable
    }

    public var resolvedPath: String {
        var resolved = path
        for (key, value) in pathValues {
            resolved = resolved.replacingOccurrences(
                of: "{\(key)}",
                with: KomaPath.percentEncodedPathValue(value)
            )
        }
        return resolved
    }

    /// The operation's cache namespace with `{placeholder}` segments replaced by `pathValues`.
    ///
    /// Placeholders that have no matching path value are left in place, exactly as
    /// `resolvedPath` leaves them.
    public var resolvedCacheNamespace: String? {
        cache.map { $0.namespace(resolvingWith: pathValues) }
    }

    /// Builds the HTTP request for this operation.
    ///
    /// Header precedence, lowest to highest: Koma's defaults (`Accept`, and `Content-Type`
    /// for a bodied request), then `headers`, then the client's plugins, which run later in
    /// `KomaClient.execute(_:operation:)`.
    func makeRequest() throws -> KomaRequest {
        var request = try KomaRequest(
            method: method,
            path: resolvedPath,
            queryItems: queryItems,
            headers: ["Accept": "application/json"],
            body: body?.data()
        )
        if request.body != nil {
            request.headers["Content-Type"] = "application/json"
        }
        for (name, value) in headers {
            request.headers[name] = value
        }
        return request
    }
}

@_documentation(visibility: private)
public struct KomaRequestBody: @unchecked Sendable {
    private let result: Result<Data, Error>

    public init(_ encode: () throws -> Data) {
        result = Result(catching: encode)
    }

    public static func data(_ data: Data) -> Self {
        Self { data }
    }

    public func data() throws -> Data {
        try result.get()
    }
}

public struct KomaPersistenceContext: Sendable {
    public let operationName: String
    public let pathValues: [String: String]
    public let queryItems: [URLQueryItem]
    public let cache: KomaCacheDescriptor?

    public init(
        operationName: String,
        pathValues: [String: String] = [:],
        queryItems: [URLQueryItem] = [],
        cache: KomaCacheDescriptor? = nil
    ) {
        self.operationName = operationName
        self.pathValues = pathValues
        self.queryItems = queryItems
        self.cache = cache
    }

    public func pathValue(_ name: String) -> String? {
        pathValues[name]
    }
}

/// Names the local cache a resource operation refreshes.
///
/// A namespace may contain `{placeholder}` segments that match the operation's path
/// placeholders. They are resolved at runtime from the operation's path values, so a
/// nested collection can be namespaced per parent:
///
/// ```swift
/// @KomaRoute(
///     .get("{projectId}/characters", as: [Character].self),
///     cache: .collection("projects/{projectId}/characters")
/// )
/// case characters(projectId: String)
/// // namespace: "collection:projects/p-1/characters"
/// ```
public struct KomaCacheDescriptor: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case collection(String)
        case entity(String)
    }

    public let kind: Kind
    public let staleAfter: KomaDuration?

    public init(kind: Kind, staleAfter: KomaDuration? = nil) {
        self.kind = kind
        self.staleAfter = staleAfter
    }

    public static func collection(_ name: String, staleAfter: KomaDuration? = nil) -> Self {
        Self(kind: .collection(name), staleAfter: staleAfter)
    }

    public static func entity(_ name: String, staleAfter: KomaDuration? = nil) -> Self {
        Self(kind: .entity(name), staleAfter: staleAfter)
    }

    public func withStaleAfter(_ staleAfter: KomaDuration?) -> Self {
        Self(kind: kind, staleAfter: staleAfter ?? self.staleAfter)
    }

    /// The stored namespace with `{placeholder}` segments replaced by `pathValues`.
    ///
    /// Path values are substituted verbatim: a namespace is a storage key, not a URL, so it
    /// is not percent encoded. Unmatched placeholders stay literal rather than failing.
    func namespace(resolvingWith pathValues: [String: String] = [:]) -> String {
        let prefix: String
        var name: String
        switch kind {
        case let .collection(value):
            prefix = "collection"
            name = value
        case let .entity(value):
            prefix = "entity"
            name = value
        }
        for (key, value) in pathValues {
            name = name.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return "\(prefix):\(name)"
    }
}

public struct KomaDuration: Equatable, Sendable {
    public let seconds: TimeInterval

    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    public static func seconds(_ value: TimeInterval) -> Self {
        Self(seconds: value)
    }

    public static func minutes(_ value: TimeInterval) -> Self {
        Self(seconds: value * 60)
    }

    public static func hours(_ value: TimeInterval) -> Self {
        Self(seconds: value * 60 * 60)
    }
}

public enum KomaFetchPolicy: Sendable {
    case localOnly
    case networkFirstFallback
    case localThenRefresh
}

/// Controls whether a resource observation completes after one refresh or stays attached to local store changes.
public enum KomaObservationMode: Sendable {
    /// Emit the current local value, refresh once, emit the refreshed local value, then finish.
    case once

    /// Keep observing the local query and emit whenever matching store tables change.
    case live
}

public enum KomaSnapshotSource: Equatable, Sendable {
    case local
    case network
    case fallback
}

public struct KomaSnapshot<Value: Sendable>: Sendable {
    public let value: Value
    public let source: KomaSnapshotSource
    public let cachedAt: Date?
    public let isRefreshing: Bool
    public let lastError: Error?

    public init(
        value: Value,
        source: KomaSnapshotSource,
        cachedAt: Date? = nil,
        isRefreshing: Bool = false,
        lastError: Error? = nil
    ) {
        self.value = value
        self.source = source
        self.cachedAt = cachedAt
        self.isRefreshing = isRefreshing
        self.lastError = lastError
    }
}
