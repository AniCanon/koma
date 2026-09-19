import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

private struct GenerationJob: Codable, Equatable {
    let id: String
    let status: String
}

struct KomaReturningCommandTests {
    @Test
    func `returning command decodes the response and sends the body through the plugins`() async throws {
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(
                statusCode: 200,
                body: JSONEncoder().encode(GenerationJob(id: "job-1", status: "queued"))
            )
        ])
        let koma = try await makeClient(transport: transport, plugins: [.bearerAuth { "token" }])

        let job: GenerationJob = try await KomaReturningCommand(
            client: koma,
            operation: KomaOperation(
                name: "generateImage",
                method: .post,
                path: "projects/{projectId}/images",
                pathValues: ["projectId": "p-1"],
                body: KomaRequestBody { Data(#"{"prompt":"sunset"}"#.utf8) }
            )
        ).perform()

        #expect(job == GenerationJob(id: "job-1", status: "queued"))

        let request = try #require(await transport.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "projects/p-1/images")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.headers["Authorization"] == "Bearer token")
        #expect(request.body == Data(#"{"prompt":"sunset"}"#.utf8))
    }

    @Test
    func `returning command throws the HTTP error before decoding a non-2xx response`() async throws {
        let body = try JSONEncoder().encode(GenerationJob(id: "job-1", status: "queued"))
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 422, body: body)
        ])
        let koma = try await makeClient(transport: transport)

        await #expect(
            throws: KomaHTTPError.invalidResponse(
                statusCode: 422,
                body: String(data: body, encoding: .utf8)
            )
        ) {
            let _: GenerationJob = try await KomaReturningCommand(
                client: koma,
                operation: KomaOperation(
                    name: "generateImage",
                    method: .post,
                    path: "projects/p-1/images"
                )
            ).perform()
        }
    }

    @Test
    func `returning command does not absorb a 404 the way a delete command does`() async throws {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 404, body: Data())
        ])
        let koma = try await makeClient(transport: transport)

        await #expect(throws: KomaHTTPError.self) {
            let _: GenerationJob = try await KomaReturningCommand(
                client: koma,
                operation: KomaOperation(
                    name: "generateImage",
                    method: .post,
                    path: "projects/p-1/images"
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
