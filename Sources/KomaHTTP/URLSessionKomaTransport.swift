import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Koma

public struct URLSessionKomaTransport: KomaConfigurableTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: borrowing KomaRequest, baseURL: URL) async throws -> KomaResponse {
        try await send(
            request,
            baseURL: baseURL,
            options: KomaTransportOptions(collectResponseHeaders: true)
        )
    }

    public func send(_ request: borrowing KomaRequest, baseURL: URL, options: KomaTransportOptions) async throws -> KomaResponse {
        let url = try Self.url(for: request, baseURL: baseURL)

        if request.method == .get, request.headers.isEmpty, request.body == nil {
            let (data, response) = try await session.data(from: url)
            return try Self.komaResponse(data: data, response: response, options: options)
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (key, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: urlRequest)
        return try Self.komaResponse(data: data, response: response, options: options)
    }

    @inline(__always)
    private static func url(for request: KomaRequest, baseURL: URL) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw KomaHTTPError.invalidURL
        }

        if !request.path.isEmpty {
            var path = KomaPath.join(components.percentEncodedPath, request.path)
            if !path.hasPrefix("/") {
                path.insert("/", at: path.startIndex)
            }
            components.percentEncodedPath = path
        }

        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
        }
        guard let resolvedURL = components.url else {
            throw KomaHTTPError.invalidURL
        }
        return resolvedURL
    }

    @inline(__always)
    private static func komaResponse(
        data: Data,
        response: URLResponse,
        options: KomaTransportOptions
    ) throws -> KomaResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw KomaHTTPError.invalidResponse(statusCode: -1, body: nil)
        }
        guard options.collectResponseHeaders else {
            return KomaResponse(statusCode: httpResponse.statusCode, body: data)
        }

        var headers: [(String, String)] = []
        headers.reserveCapacity(httpResponse.allHeaderFields.count)
        for pair in httpResponse.allHeaderFields {
            if let key = pair.key as? String {
                headers.append((key, String(describing: pair.value)))
            }
        }

        return KomaResponse(statusCode: httpResponse.statusCode, headerFields: headers, body: data)
    }
}

public extension KomaClient {
    init(
        baseURL: URL,
        store: any KomaStore,
        plugins: [any KomaHTTPPlugin] = [],
        session: URLSession = .shared,
        jsonEncoder: JSONEncoder = JSONEncoder(),
        jsonDecoder: JSONDecoder = JSONDecoder(),
        conditionalRequests: KomaConditionalRequests = .automatic
    ) {
        self.init(
            baseURL: baseURL,
            store: store,
            transport: URLSessionKomaTransport(session: session),
            plugins: plugins,
            jsonEncoder: jsonEncoder,
            jsonDecoder: jsonDecoder,
            conditionalRequests: conditionalRequests
        )
    }
}
