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

    /// Quantizes a vector to one signed byte per dimension for a compact, scan-friendly code.
    ///
    /// The vector is L2-normalized, then each component is scaled to `[-127, 127]`. The integer
    /// dot product of two codes (see `scoreInt8`) therefore ranks by cosine similarity, so a scan
    /// over int8 codes (8x smaller than `Float64`) is a fast pre-filter; rerank the candidates with
    /// full-precision `cosine` to recover the exact top-k.
    public static func encodeInt8(_ vector: [Double]) -> Data {
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        var codes = [Int8](repeating: 0, count: vector.count)
        if norm > 0 {
            let scale = 127.0 / norm
            for index in vector.indices {
                codes[index] = Int8(max(-127, min(127, (vector[index] * scale).rounded())))
            }
        }
        return codes.withUnsafeBytes { Data($0) }
    }

    /// Integer dot product of two int8 codes (see `encodeInt8`) — the per-row score of a quantized
    /// scan. Higher is more similar; the value approximates `cosine * 127 * 127`.
    public static func scoreInt8(_ a: Data, _ b: Data) -> Int {
        a.withUnsafeBytes { rawA in
            b.withUnsafeBytes { rawB in
                let codesA = rawA.bindMemory(to: Int8.self)
                let codesB = rawB.bindMemory(to: Int8.self)
                let count = min(codesA.count, codesB.count)
                var dot = 0
                for index in 0 ..< count {
                    dot += Int(codesA[index]) * Int(codesB[index])
                }
                return dot
            }
        }
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

/// Search strategy for APIs that can choose between exact vector scan and a compact quantized
/// pre-filter followed by exact reranking.
public enum KomaVectorSearchMode: Equatable, Sendable {
    case exact
    case quantized(overfetch: Int = 10)
}
