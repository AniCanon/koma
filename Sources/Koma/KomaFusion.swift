import Foundation

/// Fuses several ranked lists into one using Reciprocal Rank Fusion (RRF).
///
/// Each item's score is the sum, over the lists it appears in, of `1 / (k + rank)` (rank is
/// 1-based). Items are deduplicated by `keyPath`, keeping the first-seen instance; higher
/// combined score ranks first. `k` (default 60) damps the influence of low ranks.
///
/// This is the standard way to combine heterogeneous rankings — e.g. an FTS5 keyword ranking
/// and a vector-similarity ranking — into one hybrid result without tuning score scales.
public func komaReciprocalRankFusion<Record, ID: Hashable>(
    _ rankings: [[Record]],
    by keyPath: KeyPath<Record, ID>,
    k: Int = 60
) -> [Record] {
    var scores: [ID: Double] = [:]
    var firstSeen: [ID: Record] = [:]

    for ranking in rankings {
        for (offset, record) in ranking.enumerated() {
            let id = record[keyPath: keyPath]
            scores[id, default: 0] += 1.0 / Double(k + offset + 1)
            if firstSeen[id] == nil {
                firstSeen[id] = record
            }
        }
    }

    return scores
        .sorted { $0.value > $1.value }
        .compactMap { firstSeen[$0.key] }
}
