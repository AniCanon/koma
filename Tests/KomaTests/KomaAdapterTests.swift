import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

private struct AdapterProject: Codable, Equatable {
    let id: String
    let name: String
}

private struct AdapterProjectPage: Codable, Equatable {
    let items: [AdapterProject]
    let nextCursor: String?
}

@KomaEntity(table: "adapter_projects", as: AdapterProject.self)
private struct AdapterProjectRecord: KomaRemoteRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@KomaEntity(table: "adapter_project_pages")
private struct AdapterProjectPageRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var nextCursor: String?

    init(id: String, nextCursor: String?) {
        self.id = id
        self.nextCursor = nextCursor
    }
}

private enum AdapterProjectPageAdapter: KomaPersistenceAdapter {
    static func persist(
        _ output: AdapterProjectPage,
        context: KomaPersistenceContext,
        store: any KomaStore
    ) async throws {
        try await store.transaction { tx in
            try await tx.upsert(output.items.map(AdapterProjectRecord.init(remote:)))
            try await tx.upsert([
                AdapterProjectPageRecord(id: context.operationName, nextCursor: output.nextCursor)
            ])
        }
    }
}

@KomaResource(basePath: "adapter-projects", record: AdapterProjectRecord.self)
private enum AdapterProjectResources {
    @KomaRoute(.get(as: AdapterProjectPage.self), adapter: AdapterProjectPageAdapter.self)
    case list
}

struct KomaAdapterTests {
    @Test
    func `adapter persists records and typed metadata`() async throws {
        let store = try await makeStore()
        let transport = try FakeKomaTransport(responses: [
            KomaResponse(
                statusCode: 200,
                body: JSONEncoder().encode(
                    AdapterProjectPage(
                        items: [
                            AdapterProject(id: "1", name: "Alpha"),
                            AdapterProject(id: "2", name: "Beta")
                        ],
                        nextCursor: "cursor-2"
                    )
                )
            )
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport
        )

        let output = try await AdapterProjectResources.client(in: koma)
            .list()
            .refresh()

        #expect(output.nextCursor == "cursor-2")

        let projects = try await store.query(AdapterProjectRecord.self)
            .order(by: \.name)
            .fetch()
        #expect(projects.map(\.id) == ["1", "2"])

        let metadata = try await store.query(AdapterProjectPageRecord.self)
            .first()
        #expect(metadata == AdapterProjectPageRecord(id: "list", nextCursor: "cursor-2"))
    }

    private func makeStore() async throws -> SQLiteKomaStore {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        return try await SQLiteKomaStore(path: url.path)
    }
}
