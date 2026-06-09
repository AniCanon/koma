import Foundation

/// Vector helpers for the hybrid-search story: encode/decode embedding vectors as `Float64`
/// BLOBs and measure cosine similarity. Ranking fusion lives alongside as `KomaVector.fuse`.
public enum KomaVector {
    /// Encodes a vector as a contiguous `Float64` BLOB for storage in a `Data` column.
    /// Round-trips byte-for-byte with `decode(_:)` on a single device.
    public static func encode(_ vector: [Double]) -> Data {
        vector.withUnsafeBytes { Data($0) }
    }

    /// Encodes a vector at the given storage precision. `.float32` halves the vector-scan I/O —
    /// the right choice when the embedding source is itself single-precision (most are).
    public static func encode(_ vector: [Double], as precision: KomaVectorPrecision) -> Data {
        switch precision {
        case .float64:
            return encode(vector)
        case .float32:
            return vector.map(Float.init).withUnsafeBytes { Data($0) }
        }
    }

    /// Decodes a contiguous `Float64` BLOB (see `encode(_:)`) back into a vector.
    public static func decode(_ data: Data) -> [Double] {
        let stride = MemoryLayout<Double>.stride
        guard !data.isEmpty, data.count.isMultiple(of: stride) else { return [] }
        return data.withUnsafeBytes { raw in
            guard let baseAddress = raw.baseAddress else { return [] }
            if Int(bitPattern: baseAddress).isMultiple(of: MemoryLayout<Double>.alignment) {
                return Array(raw.bindMemory(to: Double.self))
            }

            var vector: [Double] = []
            vector.reserveCapacity(raw.count / stride)
            var offset = 0
            while offset < raw.count {
                vector.append(raw.loadUnaligned(fromByteOffset: offset, as: Double.self))
                offset += stride
            }
            return vector
        }
    }

    /// Decodes a vector BLOB written at the given precision (see `encode(_:as:)`). The precision
    /// must match the one used to encode — blob length alone cannot distinguish the two widths.
    public static func decode(_ data: Data, as precision: KomaVectorPrecision) -> [Double] {
        switch precision {
        case .float64:
            return decode(data)
        case .float32:
            let stride = MemoryLayout<Float>.stride
            guard !data.isEmpty, data.count.isMultiple(of: stride) else { return [] }
            return data.withUnsafeBytes { raw in
                (0 ..< raw.count / stride).map {
                    Double(raw.loadUnaligned(fromByteOffset: $0 * stride, as: Float.self))
                }
            }
        }
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

        // Two independent accumulators per sum break the FMA latency chain (the same shape as
        // the SQLite scan loops); a single chain leaves the FPU mostly idle.
        return a.withUnsafeBufferPointer { lhs in
            b.withUnsafeBufferPointer { rhs in
                let count = lhs.count
                var dot0 = 0.0, dot1 = 0.0
                var normA0 = 0.0, normA1 = 0.0
                var normB0 = 0.0, normB1 = 0.0
                var index = 0
                while index + 2 <= count {
                    let a0 = lhs[index], a1 = lhs[index + 1]
                    let b0 = rhs[index], b1 = rhs[index + 1]
                    dot0 += a0 * b0
                    dot1 += a1 * b1
                    normA0 += a0 * a0
                    normA1 += a1 * a1
                    normB0 += b0 * b0
                    normB1 += b1 * b1
                    index += 2
                }
                if index < count {
                    let a0 = lhs[index], b0 = rhs[index]
                    dot0 += a0 * b0
                    normA0 += a0 * a0
                    normB0 += b0 * b0
                }
                let magnitude = (normA0 + normA1).squareRoot() * (normB0 + normB1).squareRoot()
                return magnitude == 0 ? 0 : (dot0 + dot1) / magnitude
            }
        }
    }
}

/// Storage width of a vector BLOB's components (see `KomaVector.encode(_:as:)`).
public enum KomaVectorPrecision: Equatable, Sendable {
    /// 8 bytes per dimension; round-trips `Double` exactly.
    case float64
    /// 4 bytes per dimension; half the storage and scan I/O of `.float64`.
    case float32

    /// Bytes per vector component at this precision.
    public var stride: Int {
        switch self {
        case .float64: MemoryLayout<Double>.stride
        case .float32: MemoryLayout<Float>.stride
        }
    }
}

/// Search strategy for APIs that can choose between exact vector scan and a compact quantized
/// pre-filter followed by exact reranking.
public enum KomaVectorSearchMode: Equatable, Sendable {
    case exact
    case quantized(overfetch: Int = 10)
}
