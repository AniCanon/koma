import Foundation
import Koma
import KomaSQLite
import Testing

@KomaEntity(table: "normalized_memories")
private struct NormalizedMemoryRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var content: String
    var embedding: Data

    init(id: String, content: String, embedding: Data) {
        self.id = id
        self.content = content
        self.embedding = embedding
    }
}

struct KomaNormalizedVectorTests {
    private func makeStore() async throws -> SQLiteKomaStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("koma-normvec-\(UUID().uuidString).sqlite").path
        return try await SQLiteKomaStore(path: path)
    }

    private func normalized(_ vector: [Double]) -> [Double] {
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return vector.map { $0 / norm }
    }

    private func seededVectors(count: Int, dimension: Int) -> [[Double]] {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53) - 0.5
        }
        return (0 ..< count).map { _ in normalized((0 ..< dimension).map { _ in next() }) }
    }

    @Test
    func `assumeNormalized ranks identically to the exact path for normalized vectors`() async throws {
        let store = try await makeStore()
        let vectors = seededVectors(count: 32, dimension: 64)
        let records = vectors.enumerated().map { index, vector in
            NormalizedMemoryRecord(
                id: "memory-\(index)",
                content: "memory \(index)",
                embedding: KomaVector.encode(vector, as: index.isMultiple(of: 2) ? .float64 : .float32)
            )
        }
        try await store.upsert(records)

        let query = vectors[7]

        let exact = try await store.nearest(
            NormalizedMemoryRecord.self, to: query, on: \.embedding, limit: 5
        )
        let fast = try await store.nearest(
            NormalizedMemoryRecord.self, to: query, on: \.embedding, limit: 5, assumeNormalized: true
        )

        #expect(exact.map(\.record.id) == fast.map(\.record.id))
        #expect(exact.first?.record.id == "memory-7")
        for (lhs, rhs) in zip(exact, fast) {
            // Float32 storage rounds the stored components, so the two scoring paths agree
            // to storage precision, not to Double epsilon.
            #expect(abs(lhs.similarity - rhs.similarity) < 1e-6)
        }
    }

    @Test
    func `assumeNormalized quantized rerank matches the exact rerank`() async throws {
        let store = try await makeStore()
        let vectors = seededVectors(count: 32, dimension: 64)
        let records = vectors.enumerated().map { index, vector in
            NormalizedMemoryRecord(
                id: "memory-\(index)",
                content: "memory \(index)",
                embedding: KomaVector.encode(vector)
            )
        }
        try await store.upsert(records)
        try await store.createQuantizedVectorIndex(for: NormalizedMemoryRecord.self, on: \.embedding)

        let query = vectors[3]
        let exact = try await store.nearestQuantized(
            NormalizedMemoryRecord.self, to: query, on: \.embedding, limit: 5
        )
        let fast = try await store.nearestQuantized(
            NormalizedMemoryRecord.self, to: query, on: \.embedding, limit: 5, assumeNormalized: true
        )

        #expect(exact.map(\.record.id) == fast.map(\.record.id))
        #expect(fast.first?.record.id == "memory-3")
    }
}
