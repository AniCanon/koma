import Foundation

/// Controls Koma's internal JSON acceleration for simple record-shaped REST responses.
public enum KomaJSONOptimization: Equatable, Sendable {
    /// Uses Koma's optimized JSON path when the response shape and record type are supported.
    case automatic
    /// Always uses the configured `JSONDecoder`.
    case disabled
}

/// Controls conditional GET revalidation for resource refreshes.
public enum KomaConditionalRequests: Equatable, Sendable {
    /// Stores `ETag`/`Last-Modified` validators per request and sends `If-None-Match` /
    /// `If-Modified-Since` on later refreshes. A `304 Not Modified` skips the download,
    /// decode, and upsert; the local store already holds the current data.
    case automatic
    /// Never sends conditional headers and never stores validators.
    case disabled
}

/// Coordinates Koma storage, transport, plugins, coding, and refresh state.
///
/// Create one client at an app or feature boundary and inject it into your
/// repositories. Resource clients and model queries are lightweight values built
/// from this client.
///
/// ```swift
/// let koma = KomaClient(
///     baseURL: apiBaseURL,
///     store: store,
///     transport: URLSessionKomaTransport(),
///     plugins: [
///         .bearerAuth { try await tokenProvider.token() },
///         .retry(maxAttempts: 3)
///     ]
/// )
///
/// let projects = ProjectResources.client(in: koma)
/// ```
public struct KomaClient: @unchecked Sendable {
    public let baseURL: URL
    public let store: any KomaStore
    public let transport: any KomaTransport
    public let plugins: [any KomaHTTPPlugin]
    public let jsonEncoder: JSONEncoder
    public let jsonDecoder: JSONDecoder
    public let jsonOptimization: KomaJSONOptimization
    public let conditionalRequests: KomaConditionalRequests
    let refreshScheduler: KomaRefreshScheduler

    /// Creates a Koma client.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL used to resolve relative resource paths.
    ///   - store: The normalized local store.
    ///   - transport: The HTTP transport implementation.
    ///   - plugins: Request plugins for auth, retry, logging, or validation.
    ///   - jsonEncoder: The encoder used for request bodies.
    ///   - jsonDecoder: The fallback decoder used for REST responses.
    ///   - jsonOptimization: Controls Koma's optimized JSON path for supported record-shaped responses.
    ///   - conditionalRequests: Controls `ETag`/`Last-Modified` revalidation for refreshes.
    public init(
        baseURL: URL,
        store: any KomaStore,
        transport: any KomaTransport,
        plugins: [any KomaHTTPPlugin] = [],
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder(),
        jsonOptimization: KomaJSONOptimization = .automatic,
        conditionalRequests: KomaConditionalRequests = .automatic
    ) {
        self.baseURL = baseURL
        self.store = store
        self.transport = transport
        self.plugins = plugins
        self.jsonEncoder = jsonEncoder
        self.jsonDecoder = jsonDecoder
        self.jsonOptimization = jsonOptimization
        self.conditionalRequests = conditionalRequests
        refreshScheduler = KomaRefreshScheduler(store: store)
    }

    public func execute(
        _ request: KomaRequest,
        operation: String,
        collectResponseHeaders: Bool = true,
        acceptNotModified: Bool = false
    ) async throws -> KomaResponse {
        if plugins.isEmpty {
            let response = try await send(request, collectResponseHeaders: collectResponseHeaders)
            if acceptNotModified, response.statusCode == 304 {
                return response
            }
            try Self.validateSuccessfulResponse(response)
            return response
        }

        var attempt = 1

        while true {
            let context = KomaRequestContext(operation: operation, attempt: attempt)

            do {
                var prepared = request
                for plugin in plugins {
                    prepared = try await plugin.prepare(prepared, context: context)
                }

                let response = try await send(prepared, collectResponseHeaders: collectResponseHeaders)
                if acceptNotModified, response.statusCode == 304 {
                    return response
                }
                try Self.validateSuccessfulResponse(response)

                for plugin in plugins {
                    try await plugin.validate(response, context: context)
                }

                return response
            } catch {
                var shouldRetry = false
                for plugin in plugins where try await plugin.recover(error, context: context) == .retry {
                    shouldRetry = true
                }
                if shouldRetry {
                    attempt += 1
                    continue
                }
                throw error
            }
        }
    }

    @inline(__always)
    private func send(_ request: borrowing KomaRequest, collectResponseHeaders: Bool) async throws -> KomaResponse {
        if let configurableTransport = transport as? any KomaConfigurableTransport {
            return try await configurableTransport.send(
                request,
                baseURL: baseURL,
                options: KomaTransportOptions(collectResponseHeaders: collectResponseHeaders)
            )
        }
        return try await transport.send(request, baseURL: baseURL)
    }

    @inline(__always)
    private static func validateSuccessfulResponse(_ response: KomaResponse) throws {
        guard 200 ..< 300 ~= response.statusCode else {
            throw KomaHTTPError.invalidResponse(
                statusCode: response.statusCode,
                body: String(data: response.body, encoding: .utf8)
            )
        }
    }
}

public protocol KomaResourceNamespace {
    associatedtype Client

    static func client(in koma: KomaClient) -> Client
}

public extension KomaClient {
    /// Creates a macro-expanded resource client for a resource namespace.
    ///
    /// ```swift
    /// let projects = koma.resource(ProjectResources.self)
    /// let snapshot = try await projects.list().fetch()
    /// ```
    func resource<Resource: KomaResourceNamespace>(_ resource: Resource.Type) -> Resource.Client {
        resource.client(in: self)
    }

    /// Creates a lazy model query against the client's store.
    ///
    /// ```swift
    /// let projects = try await koma.query(ProjectModel.self)
    ///     .include(\.characters)
    ///     .fetch()
    /// ```
    func query<Model: KomaModel>(_ model: Model.Type) -> KomaModelQuery<Model> {
        store.query(model)
    }

    /// Refreshes registered requests whose policies are due.
    ///
    /// Call this from platform background schedulers such as `BGTaskScheduler`
    /// on iOS or WorkManager on Android.
    func refreshDueRegistrations(now: Date = Date()) async throws -> [KomaRefreshResult] {
        try await refreshScheduler.refreshDueRegistrations(now: now)
    }

    /// Returns the concrete requests currently registered for refresh.
    func refreshRegistrations() async throws -> [KomaRefreshRegistrationRecord] {
        try await refreshScheduler.registrations()
    }

    /// Clears refresh registrations, optionally scoped to a user or tenant.
    ///
    /// Use this during logout or tenant switching.
    func clearRefreshRegistrations(userScope: String? = nil) async throws {
        try await refreshScheduler.clearRegistrations(userScope: userScope)
    }
}
