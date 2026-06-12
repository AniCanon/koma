import CKomaSQLite
import Foundation
import Koma

/// Bounded top-k selector: a min-heap whose root is the worst kept score, so a full table scan
/// keeps the best `k` rows without accumulating — and then sorting — every scored row.
private struct VectorTopK<Score: Comparable> {
    private var heap: [(score: Score, rowid: Int64)] = []
    private let capacity: Int

    init(_ capacity: Int) {
        self.capacity = capacity
    }

    mutating func insert(_ score: Score, rowid: Int64) {
        if heap.count < capacity {
            heap.append((score, rowid))
            var child = heap.count - 1
            while child > 0 {
                let parent = (child - 1) / 2
                guard heap[child].score < heap[parent].score else { break }
                heap.swapAt(child, parent)
                child = parent
            }
        } else if score > heap[0].score {
            heap[0] = (score, rowid)
            var parent = 0
            while true {
                let left = parent * 2 + 1
                guard left < heap.count else { break }
                let right = left + 1
                let smallest = right < heap.count && heap[right].score < heap[left].score ? right : left
                guard heap[smallest].score < heap[parent].score else { break }
                heap.swapAt(parent, smallest)
                parent = smallest
            }
        }
    }

    /// Kept rows, best score first.
    func sortedDescending() -> [(score: Score, rowid: Int64)] {
        heap.sorted { $0.score > $1.score }
    }
}

/// The in-place scan layer of the vector search APIs: streams `(rowid, blob)` straight off
/// SQLite row buffers, scores with unrolled kernels, and keeps the top `limit` in a bounded
/// heap. Shared by the public entry points in `SQLiteKomaStoreVector.swift` on both writer
/// and pooled read connections.
extension SQLiteKomaStore {
    /// Streams `(rowid, embedding)` from `table.column` and returns the `limit` rows whose vector is
    /// most cosine-similar to `query`. Each blob is scored directly off SQLite's row buffer — no
    /// `Data` copy and no `[Double]` is allocated per row; a bounded min-heap keeps the top `limit`
    /// so the scan never sorts the whole table. `table`/`column` must be pre-quoted.
    static func scoreVectorColumn(
        table: String,
        column: String,
        to query: [Double],
        limit: Int,
        assumeNormalized: Bool = false,
        access: SQLiteDatabaseAccess
    ) throws -> [(rowid: Int64, similarity: Double)] {
        let float64Bytes = query.count * MemoryLayout<Double>.stride
        let float32Bytes = query.count * MemoryLayout<Float>.stride
        // The query's own norm is constant across rows, so hoist it out of the scan.
        let queryNorm = query.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard queryNorm > 0 else { return [] }

        return try query.withUnsafeBufferPointer { queryBuffer in
            try access.withStatement("SELECT rowid, \(column) FROM \(table)") { statement in
                var top = VectorTopK<Double>(limit)
                while true {
                    switch sqlite3_step(statement) {
                    case SQLITE_ROW:
                        guard let bytes = sqlite3_column_blob(statement, 1) else { continue }
                        let similarity: Double
                        switch (Int(sqlite3_column_bytes(statement, 1)), assumeNormalized) {
                        case (float64Bytes, true):
                            similarity = Self.dot(queryBuffer, float64: bytes)
                        case (float32Bytes, true):
                            similarity = Self.dot(queryBuffer, float32: bytes)
                        case (float64Bytes, false):
                            let scored = Self.dotAndNorm(queryBuffer, float64: bytes)
                            let magnitude = queryNorm * scored.norm.squareRoot()
                            similarity = magnitude == 0 ? 0 : scored.dot / magnitude
                        case (float32Bytes, false):
                            let scored = Self.dotAndNorm(queryBuffer, float32: bytes)
                            let magnitude = queryNorm * scored.norm.squareRoot()
                            similarity = magnitude == 0 ? 0 : scored.dot / magnitude
                        default:
                            continue // skip rows whose vector is absent or a different dimension
                        }
                        top.insert(similarity, rowid: sqlite3_column_int64(statement, 0))
                    case SQLITE_DONE:
                        return top.sortedDescending().map { (rowid: $0.rowid, similarity: $0.score) }
                    default:
                        throw Self.stepError(statement)
                    }
                }
            }
        }
    }

    /// Scans the int8 sidecar for candidates, then reranks those candidates with exact
    /// full-precision cosine using the base table's original embedding blob. Inputs must be
    /// pre-quoted.
    static func scoreQuantizedVectorIndex(
        selection: (indexTable: String, baseTable: String, column: String),
        to query: [Double],
        limit: Int,
        overfetch: Int,
        assumeNormalized: Bool = false,
        access: SQLiteDatabaseAccess
    ) throws -> [(rowid: Int64, similarity: Double)] {
        let queryCode = KomaVector.encodeInt8(query)
        let dimension = queryCode.count
        guard dimension > 0 else { return [] }

        let candidateLimit = max(limit, limit * overfetch)
        let candidates = try queryCode.withUnsafeBytes { raw -> [Int64] in
            let queryCodes = raw.bindMemory(to: Int8.self)
            return try access.withStatement("SELECT rowid, code FROM \(selection.indexTable)") { statement in
                var top = VectorTopK<Int>(candidateLimit)
                while true {
                    switch sqlite3_step(statement) {
                    case SQLITE_ROW:
                        guard Int(sqlite3_column_bytes(statement, 1)) == dimension,
                              let bytes = sqlite3_column_blob(statement, 1)
                        else {
                            continue
                        }
                        top.insert(
                            Self.dotInt8(queryCodes, bytes: bytes),
                            rowid: sqlite3_column_int64(statement, 0)
                        )
                    case SQLITE_DONE:
                        return top.sortedDescending().map(\.rowid)
                    default:
                        throw Self.stepError(statement)
                    }
                }
            }
        }
        guard !candidates.isEmpty else { return [] }

        let queryNorm = query.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard queryNorm > 0 else { return [] }

        let float64Bytes = query.count * MemoryLayout<Double>.stride
        let float32Bytes = query.count * MemoryLayout<Float>.stride
        let ids = candidates.map(String.init).joined(separator: ", ")
        return try query.withUnsafeBufferPointer { queryBuffer in
            try access.withStatement("SELECT rowid, \(selection.column) FROM \(selection.baseTable) WHERE rowid IN (\(ids))") { statement in
                var top = VectorTopK<Double>(limit)
                while true {
                    switch sqlite3_step(statement) {
                    case SQLITE_ROW:
                        guard let bytes = sqlite3_column_blob(statement, 1) else { continue }
                        let similarity: Double
                        switch (Int(sqlite3_column_bytes(statement, 1)), assumeNormalized) {
                        case (float64Bytes, true):
                            similarity = Self.dot(queryBuffer, float64: bytes)
                        case (float32Bytes, true):
                            similarity = Self.dot(queryBuffer, float32: bytes)
                        case (float64Bytes, false):
                            let scored = Self.dotAndNorm(queryBuffer, float64: bytes)
                            let magnitude = queryNorm * scored.norm.squareRoot()
                            similarity = magnitude == 0 ? 0 : scored.dot / magnitude
                        case (float32Bytes, false):
                            let scored = Self.dotAndNorm(queryBuffer, float32: bytes)
                            let magnitude = queryNorm * scored.norm.squareRoot()
                            similarity = magnitude == 0 ? 0 : scored.dot / magnitude
                        default:
                            continue
                        }
                        top.insert(similarity, rowid: sqlite3_column_int64(statement, 0))
                    case SQLITE_DONE:
                        return top.sortedDescending().map { (rowid: $0.rowid, similarity: $0.score) }
                    default:
                        throw Self.stepError(statement)
                    }
                }
            }
        }
    }

    /// Dot product and squared norm of a row's `Float64` vector against the query, read in place
    /// from SQLite's row buffer with `loadUnaligned` (the blob pointer has no alignment
    /// guarantee). Four independent accumulators break the FMA latency chain.
    private static func dotAndNorm(
        _ query: UnsafeBufferPointer<Double>,
        float64 bytes: UnsafeRawPointer
    ) -> (dot: Double, norm: Double) {
        let stride = MemoryLayout<Double>.stride
        let count = query.count
        var dot0 = 0.0, dot1 = 0.0, dot2 = 0.0, dot3 = 0.0
        var norm0 = 0.0, norm1 = 0.0, norm2 = 0.0, norm3 = 0.0
        var index = 0
        while index + 4 <= count {
            let value0 = bytes.loadUnaligned(fromByteOffset: index * stride, as: Double.self)
            let value1 = bytes.loadUnaligned(fromByteOffset: (index + 1) * stride, as: Double.self)
            let value2 = bytes.loadUnaligned(fromByteOffset: (index + 2) * stride, as: Double.self)
            let value3 = bytes.loadUnaligned(fromByteOffset: (index + 3) * stride, as: Double.self)
            dot0 += query[index] * value0
            dot1 += query[index + 1] * value1
            dot2 += query[index + 2] * value2
            dot3 += query[index + 3] * value3
            norm0 += value0 * value0
            norm1 += value1 * value1
            norm2 += value2 * value2
            norm3 += value3 * value3
            index += 4
        }
        while index < count {
            let value = bytes.loadUnaligned(fromByteOffset: index * stride, as: Double.self)
            dot0 += query[index] * value
            norm0 += value * value
            index += 1
        }
        return ((dot0 + dot1) + (dot2 + dot3), (norm0 + norm1) + (norm2 + norm3))
    }

    /// `Float32` variant of `dotAndNorm(_:float64:)`: loads single-precision components and widens
    /// them, so half the bytes cross from SQLite per row.
    private static func dotAndNorm(
        _ query: UnsafeBufferPointer<Double>,
        float32 bytes: UnsafeRawPointer
    ) -> (dot: Double, norm: Double) {
        let stride = MemoryLayout<Float>.stride
        let count = query.count
        var dot0 = 0.0, dot1 = 0.0, dot2 = 0.0, dot3 = 0.0
        var norm0 = 0.0, norm1 = 0.0, norm2 = 0.0, norm3 = 0.0
        var index = 0
        while index + 4 <= count {
            let value0 = Double(bytes.loadUnaligned(fromByteOffset: index * stride, as: Float.self))
            let value1 = Double(bytes.loadUnaligned(fromByteOffset: (index + 1) * stride, as: Float.self))
            let value2 = Double(bytes.loadUnaligned(fromByteOffset: (index + 2) * stride, as: Float.self))
            let value3 = Double(bytes.loadUnaligned(fromByteOffset: (index + 3) * stride, as: Float.self))
            dot0 += query[index] * value0
            dot1 += query[index + 1] * value1
            dot2 += query[index + 2] * value2
            dot3 += query[index + 3] * value3
            norm0 += value0 * value0
            norm1 += value1 * value1
            norm2 += value2 * value2
            norm3 += value3 * value3
            index += 4
        }
        while index < count {
            let value = Double(bytes.loadUnaligned(fromByteOffset: index * stride, as: Float.self))
            dot0 += query[index] * value
            norm0 += value * value
            index += 1
        }
        return ((dot0 + dot1) + (dot2 + dot3), (norm0 + norm1) + (norm2 + norm3))
    }

    /// Dot product only — the `assumeNormalized` kernel, where cosine reduces to the dot and the
    /// row's norm never needs accumulating. Same unrolled four-accumulator shape as `dotAndNorm`.
    private static func dot(
        _ query: UnsafeBufferPointer<Double>,
        float64 bytes: UnsafeRawPointer
    ) -> Double {
        let stride = MemoryLayout<Double>.stride
        let count = query.count
        var dot0 = 0.0, dot1 = 0.0, dot2 = 0.0, dot3 = 0.0
        var index = 0
        while index + 4 <= count {
            dot0 += query[index] * bytes.loadUnaligned(fromByteOffset: index * stride, as: Double.self)
            dot1 += query[index + 1] * bytes.loadUnaligned(fromByteOffset: (index + 1) * stride, as: Double.self)
            dot2 += query[index + 2] * bytes.loadUnaligned(fromByteOffset: (index + 2) * stride, as: Double.self)
            dot3 += query[index + 3] * bytes.loadUnaligned(fromByteOffset: (index + 3) * stride, as: Double.self)
            index += 4
        }
        while index < count {
            dot0 += query[index] * bytes.loadUnaligned(fromByteOffset: index * stride, as: Double.self)
            index += 1
        }
        return (dot0 + dot1) + (dot2 + dot3)
    }

    /// `Float32` variant of `dot(_:float64:)`.
    private static func dot(
        _ query: UnsafeBufferPointer<Double>,
        float32 bytes: UnsafeRawPointer
    ) -> Double {
        let stride = MemoryLayout<Float>.stride
        let count = query.count
        var dot0 = 0.0, dot1 = 0.0, dot2 = 0.0, dot3 = 0.0
        var index = 0
        while index + 4 <= count {
            dot0 += query[index] * Double(bytes.loadUnaligned(fromByteOffset: index * stride, as: Float.self))
            dot1 += query[index + 1] * Double(bytes.loadUnaligned(fromByteOffset: (index + 1) * stride, as: Float.self))
            dot2 += query[index + 2] * Double(bytes.loadUnaligned(fromByteOffset: (index + 2) * stride, as: Float.self))
            dot3 += query[index + 3] * Double(bytes.loadUnaligned(fromByteOffset: (index + 3) * stride, as: Float.self))
            index += 4
        }
        while index < count {
            dot0 += query[index] * Double(bytes.loadUnaligned(fromByteOffset: index * stride, as: Float.self))
            index += 1
        }
        return (dot0 + dot1) + (dot2 + dot3)
    }

    /// Integer dot of the query's int8 code against a row's code. Accumulates in `Int32` with
    /// overflow-unchecked arithmetic so the loop can vectorize — safe because `127 * 127 * count`
    /// stays inside `Int32` for any realistic embedding width.
    private static func dotInt8(_ query: UnsafeBufferPointer<Int8>, bytes: UnsafeRawPointer) -> Int {
        let codes = bytes.assumingMemoryBound(to: Int8.self)
        let count = query.count
        var dot0: Int32 = 0, dot1: Int32 = 0, dot2: Int32 = 0, dot3: Int32 = 0
        var index = 0
        while index + 4 <= count {
            dot0 &+= Int32(query[index]) &* Int32(codes[index])
            dot1 &+= Int32(query[index + 1]) &* Int32(codes[index + 1])
            dot2 &+= Int32(query[index + 2]) &* Int32(codes[index + 2])
            dot3 &+= Int32(query[index + 3]) &* Int32(codes[index + 3])
            index += 4
        }
        while index < count {
            dot0 &+= Int32(query[index]) &* Int32(codes[index])
            index += 1
        }
        return Int((dot0 &+ dot1) &+ (dot2 &+ dot3))
    }
}
