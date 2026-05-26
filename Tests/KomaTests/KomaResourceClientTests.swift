import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

struct KomaResourceClientTests {
    @Test
    func `resource client falls back to configured decoder when JSON cannot decode shape`() async throws {
        let store = try await makeStore()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let body = Data("""
        [
          {
            "id": "1",
            "name": "Alpha",
            "slug": "alpha",
            "deletedAt": "2026-01-02T03:04:05Z"
          }
        ]
        """.utf8)
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, body: body)
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport,
            jsonDecoder: decoder
        )

        let snapshot = try await ProjectResources
            .client(in: koma)
            .list()
            .fetch(policy: .networkFirstFallback)

        #expect(snapshot.value.map(\.id) == ["1"])
        #expect(snapshot.value[0].deletedAt != nil)
    }

    @Test
    func `resource client can disable JSON optimization for custom decoder strategies`() async throws {
        let store = try await makeStore()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let body = Data("""
        [
          {
            "id": "1",
            "name": "Alpha",
            "slug": "alpha",
            "deletedAt": 0
          }
        ]
        """.utf8)
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, body: body)
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport,
            jsonDecoder: decoder,
            jsonOptimization: .disabled
        )

        let snapshot = try await ProjectResources
            .client(in: koma)
            .list()
            .fetch(policy: .networkFirstFallback)

        #expect(snapshot.value.map(\.id) == ["1"])
        #expect(snapshot.value[0].deletedAt?.timeIntervalSince1970 == 0)
    }

    @Test
    func `resource client refreshes and reads through store`() async throws {
        let store = try await makeStore()
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(
                statusCode: 200,
                body: JSONEncoder().encode([
                    Project(id: "2", name: "Beta", slug: "beta", deletedAt: nil),
                    Project(id: "1", name: "Alpha", slug: "alpha", deletedAt: nil)
                ])
            )
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport,
            plugins: [.bearerAuth { "token" }]
        )

        let snapshot = try await ProjectResources.client(in: koma)
            .list(ProjectListParams(search: "a"))
            .where { $0.deletedAt == nil }
            .order(by: \.name)
            .fetch(policy: .networkFirstFallback)

        #expect(snapshot.source == .network)
        #expect(snapshot.value.map(\.id) == ["1", "2"])

        let request = await transport.requests.first
        #expect(request?.path == "projects")
        #expect(request?.queryItems.first?.name == "search")
        #expect(request?.queryItems.first?.value == "a")
        #expect(request?.headers["Authorization"] == "Bearer token")
    }

    @Test
    func `resource client uses configured encoder for query and body parameters`() async throws {
        let store = try await makeStore()
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, body: Data("[]".utf8)),
            KomaResponse(statusCode: 200, body: Data("[]".utf8)),
            KomaResponse(
                statusCode: 200,
                body: JSONEncoder().encode(Project(id: "1", name: "Alpha", slug: "alpha", deletedAt: nil))
            )
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport,
            jsonEncoder: encoder
        )
        let date = try #require(ISO8601DateFormatter().date(from: "2026-01-02T03:04:05Z"))

        _ = try await ProjectEncodingResources.client(in: koma)
            .updated(ProjectDateParams(updatedAfter: date))
            .fetch(policy: .networkFirstFallback)
        _ = try await ProjectEncodingResources.client(in: koma)
            .search(search: "alpha", page: 2)
            .fetch(policy: .networkFirstFallback)
        _ = try await ProjectEncodingResources.client(in: koma)
            .create(body: ProjectCreateBody(name: "Alpha", createdAt: date))
            .fetch(policy: .networkFirstFallback)

        let requests = await transport.requests
        #expect(requests[0].queryItems == [
            URLQueryItem(name: "updatedAfter", value: "2026-01-02T03:04:05Z")
        ])
        #expect(requests[1].queryItems == [
            URLQueryItem(name: "search", value: "alpha"),
            URLQueryItem(name: "page", value: "2")
        ])
        #expect(requests[2].body.flatMap { String(data: $0, encoding: .utf8) }?.contains("\"createdAt\":\"2026-01-02T03:04:05Z\"") == true)
    }

    @Test
    func `request body encoding failures are thrown before transport sends`() async throws {
        let store = try await makeStore()
        let transport = FakeKomaTransport()
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        do {
            _ = try await ProjectEncodingResources.client(in: koma)
                .broken(body: ProjectBrokenBody(score: .nan))
                .fetch(policy: .networkFirstFallback)
            Issue.record("Expected non-finite request body encoding to throw.")
        } catch {
            #expect(await transport.requests.isEmpty)
        }
    }

    @Test
    func `resource client percent encodes path parameters`() async throws {
        let store = try await makeStore()
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(
                statusCode: 200,
                body: JSONEncoder().encode(Project(id: "a/b c", name: "Alpha", slug: "alpha", deletedAt: nil))
            )
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        _ = try await ProjectResources.client(in: koma)
            .detail(projectId: "a/b c")
            .fetch(policy: .networkFirstFallback)

        let request = await transport.requests.first
        #expect(request?.path == "projects/a%2Fb%20c")
    }

    @Test
    func `resource client falls back to local records`() async throws {
        let store = try await makeStore()
        try await store.upsert([
            ProjectRecord(id: "1", name: "Alpha", slug: "alpha")
        ])

        let transport = FakeKomaTransport(error: URLError(.notConnectedToInternet))
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        let snapshot = try await ProjectResources.client(in: koma)
            .list()
            .fetch(policy: .networkFirstFallback)

        #expect(snapshot.source == .fallback)
        #expect(snapshot.value.map(\.id) == ["1"])
        #expect(snapshot.lastError != nil)
    }

    @Test
    func `resource live observation refreshes through local store`() async throws {
        let store = try await makeStore()
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(
                statusCode: 200,
                body: JSONEncoder().encode([
                    Project(id: "1", name: "Alpha", slug: "alpha", deletedAt: nil)
                ])
            )
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )
        let probe = ObservationProbe<KomaSnapshot<[Project]>>()
        let observation = Task {
            for await snapshot in ProjectResources.client(in: koma)
                .list()
                .observe(mode: .live)
            {
                await probe.append(snapshot)
            }
        }

        let emissions = try await withObservationTimeout(.seconds(1)) {
            await probe.waitForCount(2)
        }
        #expect(emissions.contains { $0.value.map(\.id) == ["1"] })

        observation.cancel()
    }

    private func makeStore() async throws -> SQLiteKomaStore {
        try await SQLiteKomaStore(path: makeStorePath())
    }

    private func makeStorePath() -> String {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }
}
