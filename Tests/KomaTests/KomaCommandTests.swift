import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

struct KomaCommandTests {
    @Test
    func `command sends request through plugins and evicts the row on success`() async throws {
        let store = try await makeStore()
        try await store.upsert([ProjectRecord(id: "1", name: "Alpha", slug: "alpha")])

        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 204, body: Data())
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport,
            plugins: [.bearerAuth { "token" }]
        )

        try await KomaCommand<ProjectRecord>(
            client: koma,
            operation: KomaOperation(
                name: "deleteProject",
                method: .delete,
                path: "projects/{projectId}",
                pathValues: ["projectId": "1"]
            ),
            evicting: ["1"]
        ).perform()

        let remaining = try await store.query(ProjectRecord.self).fetch()
        #expect(remaining.isEmpty)

        let request = await transport.requests.first
        #expect(request?.method == .delete)
        #expect(request?.path == "projects/1")
        #expect(request?.headers["Authorization"] == "Bearer token")
    }

    @Test
    func `command treats 404 as success and still evicts the row`() async throws {
        let store = try await makeStore()
        try await store.upsert([ProjectRecord(id: "1", name: "Alpha", slug: "alpha")])

        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 404, body: Data())
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        try await KomaCommand<ProjectRecord>(
            client: koma,
            operation: KomaOperation(
                name: "deleteProject",
                method: .delete,
                path: "projects/{projectId}",
                pathValues: ["projectId": "1"]
            ),
            evicting: ["1"]
        ).perform()

        let remaining = try await store.query(ProjectRecord.self).fetch()
        #expect(remaining.isEmpty)
    }

    @Test
    func `command rethrows non-404 errors and keeps the row`() async throws {
        let store = try await makeStore()
        try await store.upsert([ProjectRecord(id: "1", name: "Alpha", slug: "alpha")])

        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 500, body: Data())
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        await #expect(throws: KomaHTTPError.self) {
            try await KomaCommand<ProjectRecord>(
                client: koma,
                operation: KomaOperation(
                    name: "deleteProject",
                    method: .delete,
                    path: "projects/{projectId}",
                    pathValues: ["projectId": "1"]
                ),
                evicting: ["1"]
            ).perform()
        }

        let remaining = try await store.query(ProjectRecord.self).fetch()
        #expect(remaining.map(\.id) == ["1"])
    }

    @Test
    func `command rethrows 404 and keeps the row when notFoundIsSuccess is false`() async throws {
        let store = try await makeStore()
        try await store.upsert([ProjectRecord(id: "1", name: "Alpha", slug: "alpha")])

        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 404, body: Data())
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        await #expect(throws: KomaHTTPError.self) {
            try await KomaCommand<ProjectRecord>(
                client: koma,
                operation: KomaOperation(
                    name: "createProject",
                    method: .post,
                    path: "projects/{projectId}",
                    pathValues: ["projectId": "1"]
                ),
                evicting: ["1"],
                notFoundIsSuccess: false
            ).perform()
        }

        let remaining = try await store.query(ProjectRecord.self).fetch()
        #expect(remaining.map(\.id) == ["1"])
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
