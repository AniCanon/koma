import Foundation

public extension KomaVector {
    /// Fuses several ranked lists into one using Reciprocal Rank Fusion (RRF).
    ///
    /// Each item's score is the sum, over the lists it appears in, of `1 / (k + rank)` (rank is
    /// 1-based). Items are deduplicated by `keyPath`, keeping the first-seen instance; higher
    /// combined score ranks first. `k` (default 60) damps the influence of low ranks.
    ///
    /// This is the standard way to combine heterogeneous rankings — e.g. an FTS5 keyword ranking
    /// and a vector-similarity ranking — into one hybrid result without tuning score scales.
    ///
    /// Inlinable so the generic body specializes in the calling module — measured ~2x on the
    /// fusion benchmark versus the unspecialized cross-module call.
    @inlinable
    static func fuse<Record, ID: Hashable>(
        _ rankings: [[Record]],
        by keyPath: KeyPath<Record, ID>,
        k: Int = 60
    ) -> [Record] {
        // Score by (ranking, offset) position instead of copying records into a dictionary —
        // the winners are materialized once at the end, straight from the input lists.
        // `order` is the first-seen sequence number; it breaks score ties deterministically.
        var entries: [ID: (score: Double, ranking: Int, offset: Int, order: Int)] = [:]
        entries.reserveCapacity(rankings.reduce(0) { $0 + $1.count })

        for (rankingIndex, ranking) in rankings.enumerated() {
            for (offset, record) in ranking.enumerated() {
                let contribution = 1.0 / Double(k + offset + 1)
                let id = record[keyPath: keyPath]
                if let existing = entries.index(forKey: id) {
                    entries.values[existing].score += contribution
                } else {
                    entries[id] = (score: contribution, ranking: rankingIndex, offset: offset, order: entries.count)
                }
            }
        }

        return entries.values
            .sorted { $0.score > $1.score || ($0.score == $1.score && $0.order < $1.order) }
            .map { rankings[$0.ranking][$0.offset] }
    }
}
