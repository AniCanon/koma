import Foundation

public enum KomaHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case put = "PUT"
    case delete = "DELETE"
}

public struct KomaRequest: Sendable {
    public var method: KomaHTTPMethod
    public var path: String
    public var queryItems: [URLQueryItem]
    public var headers: [String: String]
    public var body: Data?

    public init(
        method: KomaHTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }
}

public struct KomaResponse: Sendable {
    public let statusCode: Int
    private let headerFields: [(String, String)]
    public let body: Data
    public var headers: [String: String] {
        var result: [String: String] = [:]
        result.reserveCapacity(headerFields.count)
        for (key, value) in headerFields {
            result[key] = value
        }
        return result
    }

    public init(statusCode: Int, headers: [String: String] = [:], body: Data) {
        self.statusCode = statusCode
        headerFields = headers.map { ($0.key, $0.value) }
        self.body = body
    }

    public init(statusCode: Int, headerFields: [(String, String)], body: Data) {
        self.statusCode = statusCode
        self.headerFields = headerFields
        self.body = body
    }
}

public struct KomaRequestContext: Sendable {
    public let operation: String
    public let attempt: Int

    public init(operation: String, attempt: Int) {
        self.operation = operation
        self.attempt = attempt
    }
}

public enum KomaRecovery: Sendable {
    case retry
}

public protocol KomaTransport: Sendable {
    func send(_ request: borrowing KomaRequest, baseURL: URL) async throws -> KomaResponse
}

public struct KomaTransportOptions: Sendable {
    public var collectResponseHeaders: Bool

    public init(collectResponseHeaders: Bool = true) {
        self.collectResponseHeaders = collectResponseHeaders
    }
}

public protocol KomaConfigurableTransport: KomaTransport {
    func send(_ request: borrowing KomaRequest, baseURL: URL, options: KomaTransportOptions) async throws -> KomaResponse
}

public protocol KomaHTTPPlugin: Sendable {
    func prepare(_ request: consuming KomaRequest, context: KomaRequestContext) async throws -> KomaRequest
    func validate(_ response: borrowing KomaResponse, context: KomaRequestContext) async throws
    func recover(_ error: Error, context: KomaRequestContext) async throws -> KomaRecovery?
}

public extension KomaHTTPPlugin {
    func prepare(_ request: consuming KomaRequest, context: KomaRequestContext) async throws -> KomaRequest {
        request
    }

    func validate(_ response: borrowing KomaResponse, context: KomaRequestContext) async throws {}

    func recover(_ error: Error, context: KomaRequestContext) async throws -> KomaRecovery? {
        nil
    }
}

public struct KomaBearerAuthPlugin: KomaHTTPPlugin {
    private let token: @Sendable () async throws -> String

    public init(token: @escaping @Sendable () async throws -> String) {
        self.token = token
    }

    public func prepare(_ request: consuming KomaRequest, context: KomaRequestContext) async throws -> KomaRequest {
        var request = request
        request.headers["Authorization"] = try await "Bearer \(token())"
        return request
    }
}

public struct KomaRetryPlugin: KomaHTTPPlugin {
    public let maxAttempts: Int

    public init(maxAttempts: Int) {
        self.maxAttempts = max(1, maxAttempts)
    }

    public func recover(_ error: Error, context: KomaRequestContext) async throws -> KomaRecovery? {
        context.attempt < maxAttempts ? .retry : nil
    }
}

public struct KomaLoggingPlugin: KomaHTTPPlugin {
    public init() {}
}

public extension KomaHTTPPlugin where Self == KomaBearerAuthPlugin {
    static func bearerAuth(_ token: @escaping @Sendable () async throws -> String) -> KomaBearerAuthPlugin {
        KomaBearerAuthPlugin(token: token)
    }
}

public extension KomaHTTPPlugin where Self == KomaRetryPlugin {
    static func retry(maxAttempts: Int) -> KomaRetryPlugin {
        KomaRetryPlugin(maxAttempts: maxAttempts)
    }
}

public extension KomaHTTPPlugin where Self == KomaLoggingPlugin {
    static func logging() -> KomaLoggingPlugin {
        KomaLoggingPlugin()
    }
}

public enum KomaHTTPError: Error, Equatable, LocalizedError {
    case invalidResponse(statusCode: Int, body: String?)
    case invalidURL

    public var errorDescription: String? {
        switch self {
        case let .invalidResponse(statusCode, body):
            return body ?? "Request failed with status \(statusCode)."
        case .invalidURL:
            return "Invalid URL."
        }
    }
}
