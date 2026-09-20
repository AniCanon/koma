import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

private struct DeviceRegistration: Codable, Equatable {
    let token: String
}

private struct Episode: Codable, Equatable {
    let id: String
    let title: String
}

private struct EpisodeJob: Codable, Equatable {
    let id: String
}

@KomaEntity(table: "void_episodes", as: Episode.self)
private struct EpisodeRecord: KomaRemoteRecord, Equatable {
    @KomaPrimaryKey var id: String
    var title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

@KomaResource(basePath: "devices")
private enum DeviceResources {
    @KomaRoute(.post("{deviceId}/register"))
    case register(deviceId: String, body: DeviceRegistration, silent: Bool = false)

    @KomaRoute(.delete("{deviceId}"))
    case unregister(deviceId: String)

    @KomaRoute(.post("{deviceId}/sessions/{sessionId}/resume"), notFoundIsSuccess: false)
    case resume(deviceId: String, sessionId: String)

    @KomaRoute(
        .post("{deviceId}/attachments"),
        headers: ["X-Koma-Upload": "raw"]
    )
    case attach(deviceId: String, headers: [String: String], body: Data)
}

@KomaResource(basePath: "projects", record: EpisodeRecord.self)
private enum EpisodeResources {
    @KomaRoute(.get("{projectId}/episodes", as: [Episode].self), cache: .collection("void_episodes"))
    case episodes(projectId: String)

    @KomaRoute(.post("{projectId}/episodes/{episodeId}/assemble", returning: EpisodeJob.self))
    case assemble(projectId: String, episodeId: String, body: DeviceRegistration)

    @KomaRoute(.post("{projectId}/episodes/{episodeId}/discard"))
    case discard(projectId: String, episodeId: String)
}

struct KomaVoidRouteTests {
    @Test
    func `void route sends its body and query items`() async throws {
        let (koma, transport) = try await makeClient(statusCode: 204)

        try await DeviceResources.client(in: koma)
            .register(deviceId: "d-1", body: DeviceRegistration(token: "abc"), silent: true)
            .perform()

        let request = try #require(await transport.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "devices/d-1/register")
        #expect(request.queryItems.map(\.name) == ["silent"])
        #expect(request.queryItems.first?.value == "true")
        #expect(request.body == Data(#"{"token":"abc"}"#.utf8))
    }

    @Test
    func `void route merges its fixed headers with the call's own and sends a data body as written`() async throws {
        let (koma, transport) = try await makeClient(statusCode: 204, plugins: [.bearerAuth { "token" }])

        try await DeviceResources.client(in: koma)
            .attach(
                deviceId: "d-1",
                headers: ["Content-Type": "multipart/form-data; boundary=koma"],
                body: Data("--koma--".utf8)
            )
            .perform()

        let request = try #require(await transport.requests.first)
        #expect(request.path == "devices/d-1/attachments")
        #expect(request.body == Data("--koma--".utf8))
        #expect(request.headers["X-Koma-Upload"] == "raw")
        #expect(request.headers["Content-Type"] == "multipart/form-data; boundary=koma")
        #expect(request.headers["Authorization"] == "Bearer token")
    }

    @Test
    func `void route absorbs a 404 and reports it by returning no response`() async throws {
        let (koma, _) = try await makeClient(statusCode: 404)

        let response = try await DeviceResources.client(in: koma)
            .unregister(deviceId: "d-1")
            .perform()

        #expect(response == nil)
    }

    @Test
    func `void route declared with notFoundIsSuccess false rethrows a 404`() async throws {
        let (koma, _) = try await makeClient(statusCode: 404)

        await #expect(throws: KomaHTTPError.self) {
            try await DeviceResources.client(in: koma)
                .resume(deviceId: "d-1", sessionId: "s-1")
                .perform()
        }
    }

    @Test
    func `a namespace mixes stored, returning, and void routes`() async throws {
        let store = try await makeStore()
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, body: JSONEncoder().encode([Episode(id: "e-1", title: "Pilot")])),
            KomaResponse(statusCode: 200, body: JSONEncoder().encode(EpisodeJob(id: "job-1"))),
            KomaResponse(statusCode: 204, body: Data())
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )
        let client = EpisodeResources.client(in: koma)

        let snapshot = try await client.episodes(projectId: "p-1").fetch(policy: .networkFirstFallback)
        #expect(snapshot.value.map(\.id) == ["e-1"])

        let job = try await client
            .assemble(projectId: "p-1", episodeId: "e-1", body: DeviceRegistration(token: "abc"))
            .perform()
        #expect(job == EpisodeJob(id: "job-1"))

        let response = try await client.discard(projectId: "p-1", episodeId: "e-1").perform()
        #expect(response?.statusCode == 204)

        let paths = await transport.requests.map(\.path)
        #expect(paths == [
            "projects/p-1/episodes",
            "projects/p-1/episodes/e-1/assemble",
            "projects/p-1/episodes/e-1/discard"
        ])

        let stored = try await store.query(EpisodeRecord.self).fetch()
        #expect(stored.map(\.id) == ["e-1"])
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

    private func makeClient(
        statusCode: Int,
        plugins: [any KomaHTTPPlugin] = []
    ) async throws -> (KomaClient, FakeKomaTransport) {
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: statusCode, body: Data())
        ])
        let koma = try await KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: makeStore(),
            transport: transport,
            plugins: plugins
        )
        return (koma, transport)
    }
}
