import Foundation
import Koma
import KomaSQLite
import Testing

@KomaEntity(table: "memories")
private struct MemoryRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var content: String

    init(id: String, content: String) {
        self.id = id
        self.content = content
    }
}

struct KomaFullTextSearchTests {
    private func makeStore() async throws -> SQLiteKomaStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("koma-fts-\(UUID().uuidString).sqlite").path
        let store = try await SQLiteKomaStore(path: path)
        try await store.ensureSchema(for: MemoryRecord.self)
        try await store.createFullTextIndex(for: MemoryRecord.self, indexing: \.content)
        return store
    }

    @Test
    func `full-text search returns matching records ranked by relevance`() async throws {
        let store = try await makeStore()
        try await store.upsert([
            MemoryRecord(id: "1", content: "vector search with embeddings"),
            MemoryRecord(id: "2", content: "cooking pasta recipes"),
            MemoryRecord(id: "3", content: "embeddings power semantic search and embeddings again")
        ])

        let hits = try await store.fullTextSearch(MemoryRecord.self, matching: "embeddings", limit: 10)

        // Both 1 and 3 match "embeddings"; 3 has more occurrences so it ranks first. 2 does not match.
        #expect(hits.map(\.id) == ["3", "1"])
    }

    @Test
    func `creating a full-text index backfills existing rows`() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("koma-fts-backfill-\(UUID().uuidString).sqlite").path
        let store = try await SQLiteKomaStore(path: path)
        try await store.ensureSchema(for: MemoryRecord.self)
        try await store.upsert([
            MemoryRecord(id: "1", content: "existing embeddings note")
        ])

        try await store.createFullTextIndex(for: MemoryRecord.self, indexing: \.content)

        let hits = try await store.fullTextSearch(MemoryRecord.self, matching: "embeddings")
        #expect(hits.map(\.id) == ["1"])
    }

    @Test
    func `deleting a record removes it from the full-text index`() async throws {
        let store = try await makeStore()
        try await store.upsert([MemoryRecord(id: "1", content: "embeddings rule")])
        #expect(try await store.fullTextSearch(MemoryRecord.self, matching: "embeddings").map(\.id) == ["1"])

        _ = try await store.delete(MemoryRecord.self).where { $0.id == "1" }.execute()

        #expect(try await store.fullTextSearch(MemoryRecord.self, matching: "embeddings").isEmpty)
    }

    @Test
    func `updating a record's text re-indexes it`() async throws {
        let store = try await makeStore()
        try await store.upsert([MemoryRecord(id: "1", content: "embeddings rule")])

        try await store.upsert([MemoryRecord(id: "1", content: "cooking pasta recipes")])

        #expect(try await store.fullTextSearch(MemoryRecord.self, matching: "embeddings").isEmpty)
        #expect(try await store.fullTextSearch(MemoryRecord.self, matching: "cooking").map(\.id) == ["1"])
    }
}
