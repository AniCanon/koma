import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

struct KomaVoidCommandTests {
    @Test
    func `void command sends the request through the plugins`() async throws {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 204, body: Data())
        ])
        let koma = try await makeClient(transport: transport, plugins: [.bearerAuth { "token" }])

        let response = try await KomaVoidCommand(
            client: koma,
            operation: KomaOperation(
                name: "retryRender",
                method: .post,
                path: "projects/{projectId}/renders/{renderId}/retry",
                pathValues: ["projectId": "p-1", "renderId": "r-1"]
            )
        ).perform()

        #expect(response?.statusCode == 204)

        let request = try #require(await transport.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "projects/p-1/renders/r-1/retry")
        #expect(request.headers["Authorization"] == "Bearer token")
    }

    @Test
    func `void command absorbs a 404 as success`() async throws {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 404, body: Data())
        ])
        let koma = try await makeClient(transport: transport)

        let response = try await KomaVoidCommand(
            client: koma,
            operation: KomaOperation(
                name: "unregisterDevice",
                method: .delete,
                path: "devices/{deviceId}",
                pathValues: ["deviceId": "d-1"]
            )
        ).perform()

        #expect(response == nil)
    }

    @Test
    func `void command rethrows a 404 when notFoundIsSuccess is false`() async throws {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 404, body: Data())
        ])
        let koma = try await makeClient(transport: transport)

        await #expect(throws: KomaHTTPError.self) {
            try await KomaVoidCommand(
                client: koma,
                operation: KomaOperation(
                    name: "retryRender",
                    method: .post,
                    path: "renders/{renderId}/retry",
                    pathValues: ["renderId": "r-1"]
                ),
                notFoundIsSuccess: false
            ).perform()
        }
    }

    @Test
    func `void command throws on a non-2xx response`() async throws {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 500, body: Data())
        ])
        let koma = try await makeClient(transport: transport)

        await #expect(throws: KomaHTTPError.self) {
            try await KomaVoidCommand(
                client: koma,
                operation: KomaOperation(
                    name: "retryRender",
                    method: .post,
                    path: "renders/{renderId}/retry",
                    pathValues: ["renderId": "r-1"]
                )
            ).perform()
        }
    }

    private func makeClient(
        transport: FakeKomaTransport,
        plugins: [any KomaHTTPPlugin] = []
    ) async throws -> KomaClient {
        let store = try await SQLiteKomaStore(
            path: FileManager.default
                .temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("sqlite")
                .path
        )
        return try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport,
            plugins: plugins
        )
    }
}
