import Foundation

/// Vector helpers for the hybrid-search story: encode/decode embedding vectors as `Float64`
/// BLOBs and measure cosine similarity. Ranking fusion lives alongside as `KomaVector.fuse`.
public enum KomaVector {
    /// Encodes a vector as a contiguous `Float64` BLOB for storage in a `Data` column.
    /// Round-trips byte-for-byte with `decode(_:)` on a single device.
    public static func encode(_ vector: [Double]) -> Data {
        vector.withUnsafeBytes { Data($0) }
    }

    /// Decodes a contiguous `Float64` BLOB (see `encode(_:)`) back into a vector.
    public static func decode(_ data: Data) -> [Double] {
        guard !data.isEmpty else { return [] }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
    }

    /// Cosine similarity of two equal-length vectors, in `[-1, 1]`.
    ///
    /// Returns `0` when the vectors differ in length, are empty, or either has zero magnitude.
    public static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot = 0.0
        var normA = 0.0
        var normB = 0.0
        for index in a.indices {
            dot += a[index] * b[index]
            normA += a[index] * a[index]
            normB += b[index] * b[index]
        }

        let magnitude = normA.squareRoot() * normB.squareRoot()
        return magnitude == 0 ? 0 : dot / magnitude
    }
}
