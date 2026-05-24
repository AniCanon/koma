import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

struct KomaContextTests {
    @Test
    func `resource client can resolve from task local context`() async throws {
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

        let snapshot = try await KomaContext.withClient(koma) {
            try await ProjectResources.client()
                .list()
                .fetch(policy: .networkFirstFallback)
        }

        #expect(snapshot.source == .network)
        #expect(snapshot.value.map(\.id) == ["1"])
    }

    @Test
    func `resource client requires task local context when no client is passed`() {
        do {
            _ = try ProjectResources.client()
            Issue.record("Expected missing client error.")
        } catch {
            #expect(error as? KomaContextError == .missingClient)
        }
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
