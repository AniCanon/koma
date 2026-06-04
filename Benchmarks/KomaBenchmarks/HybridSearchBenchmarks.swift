import Benchmark
import Foundation
import Koma
import KomaBenchmarkSupport
import KomaMacros
import KomaSQLite

/// A record with both a free-text column (FTS5) and a Float64 embedding column (vector recall),
/// mirroring the shape a local AI-memory store uses.
@KomaEntity(table: "benchmark_memories")
struct BenchmarkMemoryRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var content: String
    var embedding: Data

    init(id: String, content: String, embedding: [Double]) {
        self.id = id
        self.content = content
        self.embedding = KomaVector.encode(embedding)
    }
}

enum MemoryBenchmarkFixtures {
    static let dimension = 384
    static let corpus = 10000

    private static let vocabulary = [
        "memory", "swift", "vector", "search", "context", "agent",
        "local", "model", "recall", "fusion", "embedding", "query"
    ]

    /// Deterministic pseudo-vector in `[-0.5, 0.5)` — an LCG keeps fixtures reproducible across
    /// runs (no `Math.random`) and portable (no trig/platform math).
    static func vector(seed: UInt64) -> [Double] {
        var state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1
        var out = [Double](repeating: 0, count: dimension)
        for index in 0 ..< dimension {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            out[index] = Double(state >> 11) * (1.0 / 9_007_199_254_740_992.0) - 0.5
        }
        return out
    }

    static func content(_ index: Int) -> String {
        let first = vocabulary[index % vocabulary.count]
        let second = vocabulary[(index / 7) % vocabulary.count]
        return "\(first) \(second) note \(index)"
    }

    static let vectors: [[Double]] = (0 ..< corpus).map { vector(seed: UInt64($0)) }
    static let query: [Double] = vector(seed: 0xABCD)
    static let records: [BenchmarkMemoryRecord] = (0 ..< corpus).map {
        BenchmarkMemoryRecord(id: "\($0)", content: content($0), embedding: vectors[$0])
    }

    static let blobs: [Data] = vectors.map(KomaVector.encode)

    static func store(_ label: String) async throws -> SQLiteKomaStore {
        try await BenchmarkFixtureCache.shared.value(label) {
            let path = BenchmarkFixtures.databasePath(label)
            let store = try await SQLiteKomaStore(path: path)
            try await store.ensureSchema(for: BenchmarkMemoryRecord.self)
            try await store.createFullTextIndex(for: BenchmarkMemoryRecord.self, indexing: \.content)
            try await store.upsert(records)
            return store
        }
    }
}

func registerHybridSearchBenchmarks() {
    let fixtures = MemoryBenchmarkFixtures.self

    // MARK: Compute primitives (no DB) — isolate the cosine inner loop and codec.

    Benchmark("koma.vector.cosineScan.10k.dim384") { benchmark in
        let query = fixtures.query
        let vectors = fixtures.vectors
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            var best = -1.0
            for candidate in vectors {
                best = max(best, KomaVector.cosine(query, candidate))
            }
            blackHole(best)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("koma.vector.encode.1k.dim384") { benchmark in
        let vectors = Array(fixtures.vectors.prefix(1000))
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            for vector in vectors {
                blackHole(KomaVector.encode(vector))
            }
        }
        benchmark.stopMeasurement()
    }

    Benchmark("koma.vector.decode.1k.dim384") { benchmark in
        let blobs = Array(fixtures.blobs.prefix(1000))
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            for blob in blobs {
                blackHole(KomaVector.decode(blob))
            }
        }
        benchmark.stopMeasurement()
    }

    Benchmark("koma.fusion.rrf.2x1k") { benchmark in
        let keyword = Array(fixtures.records.prefix(1000))
        let semantic = Array(fixtures.records.suffix(1000))
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let fused = KomaVector.fuse([keyword, semantic], by: \.id)
            blackHole(fused.count)
        }
        benchmark.stopMeasurement()
    }

    // MARK: End-to-end store paths over a 10k corpus.

    Benchmark("koma.sqlite.fullTextSearch.10k") { benchmark in
        let store = try await fixtures.store("koma-memories-fts")
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let hits = try await store.fullTextSearch(BenchmarkMemoryRecord.self, matching: "swift", limit: 20)
            blackHole(hits.count)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("koma.sqlite.nearest.10k.dim384") { benchmark in
        let store = try await fixtures.store("koma-memories-nearest")
        let query = fixtures.query
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let near = try await store.nearest(BenchmarkMemoryRecord.self, to: query, on: \.embedding, limit: 20)
            blackHole(near.count)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("koma.sqlite.hybridSearch.10k.dim384") { benchmark in
        let store = try await fixtures.store("koma-memories-hybrid")
        let query = fixtures.query
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let results = try await store.hybridSearch(
                BenchmarkMemoryRecord.self,
                matching: "swift",
                near: query,
                on: \.embedding,
                identifiedBy: \.id,
                limit: 20
            )
            blackHole(results.count)
        }
        benchmark.stopMeasurement()
    }
}
