import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

private struct Faction: Codable, Equatable {
    let id: String
    let name: String
}

@KomaEntity(table: "parameter_factions", as: Faction.self)
private struct FactionRecord: KomaRemoteRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

private struct FactionParams: Codable, Equatable {
    var search: String?
    var page: Int

    init(search: String? = nil, page: Int = 5) {
        self.search = search
        self.page = page
    }
}

@KomaResource(basePath: "projects", record: FactionRecord.self)
private enum FactionResources {
    @KomaRoute(.get("{projectId}/factions", as: [Faction].self), cache: .collection("factions"))
    case factions(projectId: String, _ params: FactionParams = .init())

    @KomaRoute(.get("{projectId}/factions/labelled", as: [Faction].self))
    case labelled(projectId: String, search: String?, page: Int = 1)

    @KomaRoute(.get("factions", as: [Faction].self))
    case bare(FactionParams = .init())
}

struct KomaResourceParameterTests {
    @Test
    func `unlabeled parameter in second position binds its local name`() async throws {
        let (koma, transport) = try await makeClient()

        let snapshot = try await FactionResources.client(in: koma)
            .factions(projectId: "p-1", FactionParams(search: "sun", page: 2))
            .fetch(policy: .networkFirstFallback)

        #expect(snapshot.value.map(\.id) == ["f-1"])

        let request = try #require(await transport.requests.first)
        #expect(request.path == "projects/p-1/factions")
        #expect(queryPairs(request) == ["page": "2", "search": "sun"])
    }

    @Test
    func `unlabeled parameter in second position keeps its default value`() async throws {
        let (koma, transport) = try await makeClient()

        _ = try await FactionResources.client(in: koma)
            .factions(projectId: "p-1")
            .fetch(policy: .networkFirstFallback)

        let request = try #require(await transport.requests.first)
        #expect(request.path == "projects/p-1/factions")
        #expect(queryPairs(request) == ["page": "5"])
    }

    @Test
    func `labelled parameters encode as named query items`() async throws {
        let (koma, transport) = try await makeClient()

        _ = try await FactionResources.client(in: koma)
            .labelled(projectId: "p-1", search: "sun", page: 3)
            .fetch(policy: .networkFirstFallback)

        let request = try #require(await transport.requests.first)
        #expect(request.path == "projects/p-1/factions/labelled")
        #expect(queryPairs(request) == ["page": "3", "search": "sun"])
    }

    @Test
    func `bare unlabeled parameter encodes as a query struct`() async throws {
        let (koma, transport) = try await makeClient()

        _ = try await FactionResources.client(in: koma)
            .bare(FactionParams(search: "sun"))
            .fetch(policy: .networkFirstFallback)

        let request = try #require(await transport.requests.first)
        #expect(request.path == "projects/factions")
        #expect(queryPairs(request) == ["page": "5", "search": "sun"])
    }

    private func queryPairs(_ request: KomaRequest) -> [String: String] {
        var pairs: [String: String] = [:]
        for item in request.queryItems {
            pairs[item.name] = item.value
        }
        return pairs
    }

    private func makeClient() async throws -> (KomaClient, FakeKomaTransport) {
        let store = try await SQLiteKomaStore(
            path: FileManager.default
                .temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("sqlite")
                .path
        )
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(
                statusCode: 200,
                body: JSONEncoder().encode([Faction(id: "f-1", name: "Sunward")])
            )
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )
        return (koma, transport)
    }
}
