import Foundation
import Koma
import KomaMacros
import KomaSQLite
import KomaTesting
import Testing

private struct RefreshProject: Codable, Equatable {
    let id: String
    let name: String
}

@KomaEntity(table: "refresh_projects", as: RefreshProject.self)
private struct RefreshProjectRecord: KomaRemoteRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@KomaResource(basePath: "refresh-projects", record: RefreshProjectRecord.self)
private enum RefreshProjectResources {
    @KomaRoute(
        .get("{projectId}", as: RefreshProject.self),
        cache: .entity("refresh-projects", staleAfter: .minutes(15)),
        refresh: .allowed
    )
    case detail(projectId: String)

    @KomaRoute(.get(as: [RefreshProject].self), cache: .collection("refresh-projects"))
    case list
}

struct KomaRefreshTests {
    @Test
    func `keep fresh stores refresh intent and refreshes due registrations`() async throws {
        let store = try await makeStore()
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(
                statusCode: 200,
                body: JSONEncoder().encode(RefreshProject(id: "123", name: "Alpha"))
            ),
            KomaResponse(
                statusCode: 200,
                body: JSONEncoder().encode(RefreshProject(id: "123", name: "Beta"))
            )
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport,
            plugins: [.bearerAuth { "secret-token" }]
        )

        let snapshot = try await RefreshProjectResources.client(in: koma)
            .detail(projectId: "123")
            .keepFresh(.whileAuthenticated(staleAfter: .seconds(0), userScope: "user-1"))
            .fetch(policy: .networkFirstFallback)

        #expect(snapshot.value.name == "Alpha")

        let registrations = try await koma.refreshRegistrations()
        #expect(registrations.count == 1)
        #expect(registrations[0].method == "GET")
        #expect(registrations[0].path == "refresh-projects/123")
        #expect(registrations[0].cacheNamespace == "entity:refresh-projects")
        #expect(registrations[0].userScope == "user-1")
        #expect(!String(describing: registrations[0]).contains("secret-token"))

        let results = try await koma.refreshDueRegistrations()
        #expect(results == [.refreshed(registrations[0].id)])

        let refreshed = try await store.query(RefreshProjectRecord.self)
            .where { $0.id == "123" }
            .first()
        #expect(refreshed?.name == "Beta")

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.map { $0.headers["Authorization"] } == ["Bearer secret-token", "Bearer secret-token"])
    }

    @Test
    func `keep fresh requires refreshable operations`() async throws {
        let store = try await makeStore()
        let transport = FakeKomaTransport()
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        do {
            _ = try await RefreshProjectResources.client(in: koma)
                .list()
                .keepFresh(.whileAuthenticated(staleAfter: .minutes(5)))
                .fetch(policy: .networkFirstFallback)
            Issue.record("Expected non-refreshable operation to throw.")
        } catch KomaRefreshError.operationNotRefreshable("list") {}
    }

    @Test
    func `refresh due registrations skips missing handlers and removes expired records`() async throws {
        let store = try await makeStore()
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: FakeKomaTransport()
        )
        let now = Date()
        try await store.upsert([
            KomaRefreshRegistrationRecord(
                id: "expired",
                operationName: "detail",
                method: "GET",
                path: "refresh-projects/expired",
                query: "",
                cacheNamespace: "entity:refresh-projects",
                policyLifetime: KomaRefreshPolicy.Lifetime.whileRecentlyViewed.rawValue,
                staleAfterSeconds: 0,
                userScope: "user-1",
                expiresAt: now.addingTimeInterval(-1),
                lastRegisteredAt: now
            ),
            KomaRefreshRegistrationRecord(
                id: "missing",
                operationName: "detail",
                method: "GET",
                path: "refresh-projects/missing",
                query: "",
                cacheNamespace: "entity:refresh-projects",
                policyLifetime: KomaRefreshPolicy.Lifetime.untilRemoved.rawValue,
                staleAfterSeconds: 0,
                userScope: "user-1",
                expiresAt: nil,
                lastRegisteredAt: now
            )
        ])

        let results = try await koma.refreshDueRegistrations(now: now)

        #expect(results == [
            .skipped("expired", .expired),
            .skipped("missing", .missingHandler)
        ])

        let remaining = try await koma.refreshRegistrations()
        #expect(remaining.map(\.id) == ["missing"])
    }

    @Test
    func `clear refresh registrations can scope by user`() async throws {
        let store = try await makeStore()
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: FakeKomaTransport()
        )
        let now = Date()
        try await store.upsert([
            KomaRefreshRegistrationRecord(
                id: "user-1-request",
                operationName: "detail",
                method: "GET",
                path: "refresh-projects/1",
                query: "",
                cacheNamespace: "entity:refresh-projects",
                policyLifetime: KomaRefreshPolicy.Lifetime.untilRemoved.rawValue,
                staleAfterSeconds: 60,
                userScope: "user-1",
                expiresAt: nil,
                lastRegisteredAt: now
            ),
            KomaRefreshRegistrationRecord(
                id: "user-2-request",
                operationName: "detail",
                method: "GET",
                path: "refresh-projects/2",
                query: "",
                cacheNamespace: "entity:refresh-projects",
                policyLifetime: KomaRefreshPolicy.Lifetime.untilRemoved.rawValue,
                staleAfterSeconds: 60,
                userScope: "user-2",
                expiresAt: nil,
                lastRegisteredAt: now
            )
        ])

        try await koma.clearRefreshRegistrations(userScope: "user-1")

        let remaining = try await koma.refreshRegistrations()
        #expect(remaining.map(\.id) == ["user-2-request"])
    }

    private func makeStore() async throws -> SQLiteKomaStore {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        return try await SQLiteKomaStore(path: url.path)
    }
}
