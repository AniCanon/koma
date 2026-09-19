import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

private struct UploadTicket: Codable, Equatable {
    let id: String
}

@KomaEntity(table: "header_projects")
private struct HeaderProjectRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

struct KomaOperationHeaderTests {
    @Test
    func `operation headers reach the transport and plugin headers win`() async throws {
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, body: JSONEncoder().encode(UploadTicket(id: "u-1")))
        ])
        let koma = try await makeClient(transport: transport, plugins: [.bearerAuth { "token" }])

        let ticket: UploadTicket = try await KomaReturningCommand(
            client: koma,
            operation: KomaOperation(
                name: "uploadAsset",
                method: .post,
                path: "projects/{projectId}/assets",
                pathValues: ["projectId": "p-1"],
                body: KomaRequestBody { Data("--boundary--".utf8) },
                headers: [
                    "Content-Type": "multipart/form-data; boundary=boundary",
                    "Authorization": "Bearer wrong"
                ]
            )
        ).perform()

        #expect(ticket == UploadTicket(id: "u-1"))

        let request = try #require(await transport.requests.first)
        // The operation beat Koma's JSON default.
        #expect(request.headers["Content-Type"] == "multipart/form-data; boundary=boundary")
        // The plugin beat the operation.
        #expect(request.headers["Authorization"] == "Bearer token")
        #expect(request.headers["Accept"] == "application/json")
    }

    @Test
    func `operation headers reach the transport for a fetch`() async throws {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, body: Data("[]".utf8))
        ])
        let koma = try await makeClient(transport: transport)

        _ = try await KomaFetch<[Project], ProjectRecord>(
            client: koma,
            operation: KomaOperation(
                name: "list",
                method: .get,
                path: "projects",
                headers: ["X-Koma-Test": "on"]
            )
        ).fetch(policy: .networkFirstFallback)

        let request = try #require(await transport.requests.first)
        #expect(request.headers["X-Koma-Test"] == "on")
    }

    @Test
    func `operation headers reach the transport for a command`() async throws {
        let store = try await makeStore()
        try await store.upsert([HeaderProjectRecord(id: "1", name: "Alpha")])
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 204, body: Data())
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        try await KomaCommand<HeaderProjectRecord>(
            client: koma,
            operation: KomaOperation(
                name: "deleteProject",
                method: .delete,
                path: "projects/{projectId}",
                pathValues: ["projectId": "1"],
                headers: ["X-Koma-Test": "on"]
            ),
            evicting: ["1"]
        ).perform()

        let request = try #require(await transport.requests.first)
        #expect(request.headers["X-Koma-Test"] == "on")

        let remaining = try await store.query(HeaderProjectRecord.self).fetch()
        #expect(remaining.isEmpty)
    }

    private func makeClient(
        transport: FakeKomaTransport,
        plugins: [any KomaHTTPPlugin] = []
    ) async throws -> KomaClient {
        try await KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: makeStore(),
            transport: transport,
            plugins: plugins
        )
    }

    private func makeStore() async throws -> SQLiteKomaStore {
        try await SQLiteKomaStore(
            path: FileManager.default
                .temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("sqlite")
                .path
        )
    }
}
