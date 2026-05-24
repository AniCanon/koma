import Foundation
import Koma

public actor FakeKomaTransport: KomaTransport {
    public private(set) var requests: [KomaRequest] = []
    private var responses: [KomaResponse]
    private var error: Error?

    public init(responses: [KomaResponse] = [], error: Error? = nil) {
        self.responses = responses
        self.error = error
    }

    public func send(_ request: KomaRequest, baseURL: URL) async throws -> KomaResponse {
        requests.append(request)
        if let error {
            throw error
        }
        if responses.isEmpty {
            return KomaResponse(statusCode: 200, body: Data("{}".utf8))
        }
        return responses.removeFirst()
    }

    public func enqueue(_ response: KomaResponse) {
        responses.append(response)
    }

    public func fail(with error: Error?) {
        self.error = error
    }
}
