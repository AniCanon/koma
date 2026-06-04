import Foundation

public extension [Double] {
    /// Encodes this vector as a contiguous `Float64` BLOB for storage in a `Data` column.
    /// Pair with `Data.komaVector` to decode. Round-trips byte-for-byte on a single device.
    var komaVectorData: Data {
        withUnsafeBytes { Data($0) }
    }
}

public extension Data {
    /// Decodes a contiguous `Float64` BLOB (see `[Double].komaVectorData`) back into a vector.
    var komaVector: [Double] {
        guard !isEmpty else { return [] }
        return withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
    }
}

/// Cosine similarity of two equal-length vectors, in `[-1, 1]`.
///
/// Returns `0` when the vectors differ in length, are empty, or either has zero magnitude.
public func komaCosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
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
