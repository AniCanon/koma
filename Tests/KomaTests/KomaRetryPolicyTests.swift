import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

struct KomaRetryPolicyTests {
    @Test
    func `a failed read is sent again`() async throws {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 503, body: Data()),
            KomaResponse(statusCode: 200, body: Data(#"{"ok":true}"#.utf8))
        ])
        let koma = try await makeClient(transport: transport, plugins: [KomaRetryPlugin(maxAttempts: 2)])

        _ = try await koma.execute(KomaRequest(method: .get, path: "projects"), operation: "read")

        #expect(await transport.requests.count == 2)
    }

    @Test
    func `a failed write is not replayed`() async throws {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 503, body: Data()),
            KomaResponse(statusCode: 200, body: Data(#"{"ok":true}"#.utf8))
        ])
        let koma = try await makeClient(transport: transport, plugins: [KomaRetryPlugin(maxAttempts: 2)])

        await #expect(throws: (any Error).self) {
            _ = try await koma.execute(KomaRequest(method: .post, path: "projects"), operation: "write")
        }
        #expect(await transport.requests.count == 1)
    }

    @Test
    func `a write is replayed when its method is named as retryable`() async throws {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 503, body: Data()),
            KomaResponse(statusCode: 200, body: Data(#"{"ok":true}"#.utf8))
        ])
        let koma = try await makeClient(
            transport: transport,
            plugins: [KomaRetryPlugin(maxAttempts: 2, methods: [.get, .put])]
        )

        _ = try await koma.execute(KomaRequest(method: .put, path: "projects/p-1"), operation: "idempotent")

        #expect(await transport.requests.count == 2)
    }

    @Test
    func `a rejected read is not sent again`() async throws {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 422, body: Data(#"{"error":"nope"}"#.utf8)),
            KomaResponse(statusCode: 200, body: Data(#"{"ok":true}"#.utf8))
        ])
        let koma = try await makeClient(transport: transport, plugins: [KomaRetryPlugin(maxAttempts: 2)])

        await #expect(throws: (any Error).self) {
            _ = try await koma.execute(KomaRequest(method: .get, path: "projects"), operation: "rejected")
        }
        #expect(await transport.requests.count == 1)
    }

    private func makeClient(
        transport: FakeKomaTransport,
        plugins: [any KomaHTTPPlugin]
    ) async throws -> KomaClient {
        let store = try await SQLiteKomaStore(path: makeStorePath())
        return try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport,
            plugins: plugins
        )
    }

    private func makeStorePath() -> String {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }
}
