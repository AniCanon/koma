import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

private struct NamespaceCharacter: Codable, Equatable {
    let id: String
    let name: String
}

@KomaEntity(table: "namespace_characters", as: NamespaceCharacter.self)
private struct NamespaceCharacterRecord: KomaRemoteRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@KomaResource(basePath: "projects", record: NamespaceCharacterRecord.self)
private enum NamespaceResources {
    @KomaRoute(
        .get("{projectId}/characters", as: [NamespaceCharacter].self),
        cache: .collection("projects/{projectId}/characters"),
        refresh: .allowed
    )
    case characters(projectId: String)

    @KomaRoute(
        .get("{projectId}/characters/{characterId}", as: NamespaceCharacter.self),
        cache: .entity("projects/{projectId}/characters/{characterId}"),
        refresh: .allowed
    )
    case character(projectId: String, characterId: String)

    @KomaRoute(
        .get("{projectId}/missing", as: [NamespaceCharacter].self),
        cache: .collection("projects/{tenantId}/missing"),
        refresh: .allowed
    )
    case missingPlaceholder(projectId: String)

    @KomaRoute(
        .get("all", as: [NamespaceCharacter].self),
        cache: .collection("characters"),
        refresh: .allowed
    )
    case all
}

struct KomaCacheNamespaceTests {
    @Test
    func `cache namespace resolves a single path placeholder`() async throws {
        let (koma, _) = try await makeClient(listResponses: 1)

        _ = try await NamespaceResources.client(in: koma)
            .characters(projectId: "p-1")
            .keepFresh(.whileAuthenticated(staleAfter: .minutes(5)))
            .fetch(policy: .networkFirstFallback)

        let registrations = try await koma.refreshRegistrations()
        #expect(registrations.map(\.cacheNamespace) == ["collection:projects/p-1/characters"])
    }

    @Test
    func `cache namespace resolves several path placeholders`() async throws {
        let store = try await makeStore()
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(
                statusCode: 200,
                body: JSONEncoder().encode(NamespaceCharacter(id: "c-1", name: "Akira"))
            )
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        _ = try await NamespaceResources.client(in: koma)
            .character(projectId: "p-1", characterId: "c-1")
            .keepFresh(.whileAuthenticated(staleAfter: .minutes(5)))
            .fetch(policy: .networkFirstFallback)

        let registrations = try await koma.refreshRegistrations()
        #expect(registrations.map(\.cacheNamespace) == ["entity:projects/p-1/characters/c-1"])
    }

    @Test
    func `cache namespace keeps an unknown placeholder literal`() async throws {
        let (koma, _) = try await makeClient(listResponses: 1)

        _ = try await NamespaceResources.client(in: koma)
            .missingPlaceholder(projectId: "p-1")
            .keepFresh(.whileAuthenticated(staleAfter: .minutes(5)))
            .fetch(policy: .networkFirstFallback)

        let registrations = try await koma.refreshRegistrations()
        #expect(registrations.map(\.cacheNamespace) == ["collection:projects/{tenantId}/missing"])
    }

    @Test
    func `cache namespace without placeholders is stored verbatim`() async throws {
        let (koma, _) = try await makeClient(listResponses: 1)

        _ = try await NamespaceResources.client(in: koma)
            .all()
            .keepFresh(.whileAuthenticated(staleAfter: .minutes(5)))
            .fetch(policy: .networkFirstFallback)

        let registrations = try await koma.refreshRegistrations()
        #expect(registrations.map(\.cacheNamespace) == ["collection:characters"])
    }

    private func makeClient(listResponses: Int) async throws -> (KomaClient, FakeKomaTransport) {
        let store = try await makeStore()
        let body = try JSONEncoder().encode([NamespaceCharacter(id: "c-1", name: "Akira")])
        let transport = FakeKomaTransport(
            responses: Array(repeating: KomaResponse(statusCode: 200, body: body), count: listResponses)
        )
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )
        return (koma, transport)
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
