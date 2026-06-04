import Foundation
import Koma

public extension SQLiteKomaStore {
    /// Ranks records by cosine similarity of a `Float64` vector column to `vector`, best first.
    ///
    /// Brute-force over the matching rows (exact, Swift-side) — ideal for a single-device store.
    /// For large corpora, pre-filter the candidate set (e.g. with `fullTextSearch`) and rank that.
    /// The column at `keyPath` must hold a vector encoded via `[Double].komaVectorData`.
    func nearest<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        on keyPath: KeyPath<Record, Data>,
        limit: Int
    ) async throws -> [(record: Record, similarity: Double)] {
        let records = try await query(Record.self).fetch()
        let scored = records.map { record in
            (record: record, similarity: komaCosineSimilarity(vector, record[keyPath: keyPath].komaVector))
        }
        return Array(scored.sorted { $0.similarity > $1.similarity }.prefix(limit))
    }

    /// Hybrid search: fuses FTS5 keyword recall with vector (cosine) recall via Reciprocal
    /// Rank Fusion, returning the top `limit` records.
    ///
    /// Runs `fullTextSearch(matching:)` and `nearest(to:on:)` each to `candidateLimit`, then
    /// fuses the two rankings by `idKeyPath`. Requires `createFullTextIndex` to have been set up
    /// for the text column and the vector column to hold `[Double].komaVectorData`.
    func hybridSearch<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        matching query: String,
        near vector: [Double],
        on vectorKeyPath: KeyPath<Record, Data>,
        identifiedBy idKeyPath: KeyPath<Record, some Hashable>,
        limit: Int = 20,
        candidateLimit: Int = 50,
        k: Int = 60
    ) async throws -> [Record] {
        let keyword = try fullTextSearch(type, matching: query, limit: candidateLimit)
        let semantic = try await nearest(type, to: vector, on: vectorKeyPath, limit: candidateLimit).map(\.record)
        let fused = komaReciprocalRankFusion([keyword, semantic], by: idKeyPath, k: k)
        return Array(fused.prefix(limit))
    }
}
