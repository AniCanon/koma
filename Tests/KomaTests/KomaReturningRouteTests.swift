import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

private struct RenderJob: Codable, Equatable {
    let id: String
    let status: String
}

private struct RenderRequest: Codable, Equatable {
    let prompt: String
}

private struct Scene: Codable, Equatable {
    let id: String
    let name: String
}

@KomaEntity(table: "returning_scenes", as: Scene.self)
private struct SceneRecord: KomaRemoteRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@KomaResource(basePath: "projects")
private enum RenderResources {
    @KomaRoute(.post("{projectId}/renders", returning: RenderJob.self))
    case render(projectId: String, body: RenderRequest, dryRun: Bool = false)

    @KomaRoute(
        .post("{projectId}/uploads", returning: RenderJob.self),
        headers: ["X-Koma-Upload": "raw", "Content-Type": "application/octet-stream"]
    )
    case upload(projectId: String, headers: [String: String], body: Data)

    @KomaRoute(.post("{projectId}/streams", returning: RenderJob.self))
    case stream(projectId: String, body: KomaRequestBody)

    @KomaRoute(.get("capabilities", returning: RenderJob.self))
    case capabilities
}

@KomaResource(basePath: "projects", record: SceneRecord.self)
private enum SceneResources {
    @KomaRoute(.get("{projectId}/scenes", as: [Scene].self), cache: .collection("returning_scenes"))
    case scenes(projectId: String)

    @KomaRoute(.post("{projectId}/scenes/render", returning: RenderJob.self))
    case render(projectId: String, body: RenderRequest)
}

struct KomaReturningRouteTests {
    @Test
    func `returning route sends the body and decodes the response`() async throws {
        let (koma, transport) = try await makeClient(job: RenderJob(id: "job-1", status: "queued"))

        let job = try await RenderResources.client(in: koma)
            .render(projectId: "p-1", body: RenderRequest(prompt: "sunset"), dryRun: true)
            .perform()

        #expect(job == RenderJob(id: "job-1", status: "queued"))

        let request = try #require(await transport.requests.first)
        #expect(request.method == .post)
        #expect(request.path == "projects/p-1/renders")
        #expect(request.queryItems.map(\.name) == ["dryRun"])
        #expect(request.queryItems.first?.value == "true")
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(request.body == Data(#"{"prompt":"sunset"}"#.utf8))
    }

    @Test
    func `returning route with no parameters resolves its path`() async throws {
        let (koma, transport) = try await makeClient(job: RenderJob(id: "job-2", status: "ready"))

        let job = try await RenderResources.client(in: koma).capabilities().perform()

        #expect(job == RenderJob(id: "job-2", status: "ready"))

        let request = try #require(await transport.requests.first)
        #expect(request.method == .get)
        #expect(request.path == "projects/capabilities")
        #expect(request.queryItems.isEmpty)
        #expect(request.body == nil)
    }

    @Test
    func `route headers merge with the call's own headers and stay under the plugins`() async throws {
        let (koma, transport) = try await makeClient(
            job: RenderJob(id: "job-3", status: "queued"),
            plugins: [.bearerAuth { "token" }]
        )

        _ = try await RenderResources.client(in: koma)
            .upload(
                projectId: "p-1",
                headers: ["Content-Type": "multipart/form-data; boundary=koma"],
                body: Data("--koma--".utf8)
            )
            .perform()

        let request = try #require(await transport.requests.first)
        #expect(request.path == "projects/p-1/uploads")
        #expect(request.headers["Content-Type"] == "multipart/form-data; boundary=koma")
        #expect(request.headers["X-Koma-Upload"] == "raw")
        #expect(request.headers["Authorization"] == "Bearer token")
    }

    @Test
    func `a request body parameter is sent without re-encoding`() async throws {
        let (koma, transport) = try await makeClient(job: RenderJob(id: "job-6", status: "queued"))

        _ = try await RenderResources.client(in: koma)
            .stream(projectId: "p-1", body: KomaRequestBody { Data("raw-bytes".utf8) })
            .perform()

        let request = try #require(await transport.requests.first)
        #expect(request.path == "projects/p-1/streams")
        #expect(request.body == Data("raw-bytes".utf8))
    }

    @Test
    func `a data body is sent as written rather than encoded as JSON`() async throws {
        let (koma, transport) = try await makeClient(job: RenderJob(id: "job-4", status: "queued"))

        _ = try await RenderResources.client(in: koma)
            .upload(projectId: "p-1", headers: [:], body: Data("--koma--".utf8))
            .perform()

        let request = try #require(await transport.requests.first)
        #expect(request.body == Data("--koma--".utf8))
    }

    @Test
    func `a namespace mixes a stored fetch route with a returning route`() async throws {
        let store = try await makeStore()
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, body: JSONEncoder().encode([Scene(id: "s-1", name: "Dusk")])),
            KomaResponse(statusCode: 200, body: JSONEncoder().encode(RenderJob(id: "job-5", status: "queued")))
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        let snapshot = try await SceneResources.client(in: koma)
            .scenes(projectId: "p-1")
            .fetch(policy: .networkFirstFallback)
        #expect(snapshot.value.map(\.id) == ["s-1"])

        let job = try await SceneResources.client(in: koma)
            .render(projectId: "p-1", body: RenderRequest(prompt: "dusk"))
            .perform()
        #expect(job == RenderJob(id: "job-5", status: "queued"))

        let stored = try await store.query(SceneRecord.self).fetch()
        #expect(stored.map(\.id) == ["s-1"])
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
        job: RenderJob,
        plugins: [any KomaHTTPPlugin] = []
    ) async throws -> (KomaClient, FakeKomaTransport) {
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, body: JSONEncoder().encode(job))
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
