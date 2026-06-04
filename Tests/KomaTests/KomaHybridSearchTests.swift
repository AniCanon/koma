import Foundation
import Koma
import KomaMacros
import KomaSQLite
import Testing

@KomaEntity(table: "hybrid_memories")
private struct HybridMemoryRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var content: String
    var embedding: Data

    init(id: String, content: String, embedding: [Double]) {
        self.id = id
        self.content = content
        self.embedding = KomaVector.encode(embedding)
    }
}

struct KomaHybridSearchTests {
    private func makeStore() async throws -> SQLiteKomaStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("koma-hybrid-\(UUID().uuidString).sqlite").path
        let store = try await SQLiteKomaStore(path: path)
        try await store.ensureSchema(for: HybridMemoryRecord.self)
        try await store.createFullTextIndex(for: HybridMemoryRecord.self, indexing: \.content)
        return store
    }

    @Test
    func `nearest ranks records by cosine similarity to the query vector`() async throws {
        let store = try await makeStore()
        try await store.upsert([
            HybridMemoryRecord(id: "a", content: "identical", embedding: [1, 0, 0]),
            HybridMemoryRecord(id: "b", content: "orthogonal", embedding: [0, 1, 0]),
            HybridMemoryRecord(id: "c", content: "close", embedding: [0.9, 0.1, 0])
        ])

        let near = try await store.nearest(HybridMemoryRecord.self, to: [1, 0, 0], on: \.embedding, limit: 2)

        #expect(near.map(\.record.id) == ["a", "c"])
        #expect(near[0].similarity > near[1].similarity)
    }

    @Test
    func `reciprocal rank fusion merges rankings by identity`() {
        func record(_ id: String) -> HybridMemoryRecord {
            HybridMemoryRecord(id: id, content: "", embedding: [])
        }
        let a = record("a"), b = record("b"), c = record("c")

        // a is rank 1 in both lists; c appears in both (ranks 3 and 2); b appears in only one.
        let fused = KomaVector.fuse([[a, b, c], [a, c]], by: \.id, k: 60)

        #expect(fused.map(\.id) == ["a", "c", "b"])
    }

    @Test
    func `hybrid search fuses keyword and semantic recall`() async throws {
        let store = try await makeStore()
        try await store.upsert([
            // best keyword (most "embeddings") AND closest vector → wins after fusion
            HybridMemoryRecord(id: "3", content: "embeddings embeddings embeddings", embedding: [1, 0, 0]),
            // keyword-only: matches once, vector orthogonal
            HybridMemoryRecord(id: "1", content: "embeddings once", embedding: [0, 1, 0]),
            // semantic-only: no keyword match, vector close
            HybridMemoryRecord(id: "2", content: "cooking pasta", embedding: [0.9, 0.1, 0])
        ])

        let results = try await store.hybridSearch(
            HybridMemoryRecord.self,
            matching: "embeddings",
            near: [1, 0, 0],
            on: \.embedding,
            identifiedBy: \.id,
            limit: 3
        )

        #expect(results.map(\.id) == ["3", "1", "2"])
    }
}
