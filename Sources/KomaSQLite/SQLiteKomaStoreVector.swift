import CKomaSQLite
import Foundation
import Koma

/// Shared body of the `koma_vector_i8` overloads: quantizes a `Float64` or `Float32` vector blob
/// to one signed byte per dimension (the SQL-side mirror of `KomaVector.encodeInt8`).
private func komaVectorInt8Result(
    _ context: OpaquePointer?,
    value: OpaquePointer?,
    elementStride: Int
) {
    guard let value, sqlite3_value_type(value) == SQLITE_BLOB else {
        sqlite3_result_null(context)
        return
    }

    let byteCount = Int(sqlite3_value_bytes(value))
    guard byteCount.isMultiple(of: elementStride) else {
        sqlite3_result_null(context)
        return
    }

    let dimension = byteCount / elementStride
    guard dimension > 0 else {
        sqlite3_result_blob(context, nil, 0, SQLITE_TRANSIENT)
        return
    }

    guard let bytes = sqlite3_value_blob(value) else {
        sqlite3_result_null(context)
        return
    }

    func component(_ index: Int) -> Double {
        elementStride == MemoryLayout<Double>.stride
            ? bytes.loadUnaligned(fromByteOffset: index * elementStride, as: Double.self)
            : Double(bytes.loadUnaligned(fromByteOffset: index * elementStride, as: Float.self))
    }

    var norm = 0.0
    for index in 0 ..< dimension {
        let value = component(index)
        norm += value * value
    }

    var codes = [Int8](repeating: 0, count: dimension)
    if norm > 0 {
        let scale = 127.0 / norm.squareRoot()
        for index in 0 ..< dimension {
            codes[index] = Int8(max(-127, min(127, (component(index) * scale).rounded())))
        }
    }

    codes.withUnsafeBytes { raw in
        sqlite3_result_blob(context, raw.baseAddress, Int32(raw.count), SQLITE_TRANSIENT)
    }
}

private let sqliteKomaVectorInt8: @convention(c) (
    OpaquePointer?,
    Int32,
    UnsafeMutablePointer<OpaquePointer?>?
) -> Void = { context, argc, values in
    guard argc == 1, let values else {
        sqlite3_result_null(context)
        return
    }
    komaVectorInt8Result(context, value: values[0], elementStride: MemoryLayout<Double>.stride)
}

private let sqliteKomaVectorInt8Stride: @convention(c) (
    OpaquePointer?,
    Int32,
    UnsafeMutablePointer<OpaquePointer?>?
) -> Void = { context, argc, values in
    guard argc == 2, let values else {
        sqlite3_result_null(context)
        return
    }
    let elementStride = Int(sqlite3_value_int64(values[1]))
    guard elementStride == MemoryLayout<Double>.stride || elementStride == MemoryLayout<Float>.stride else {
        sqlite3_result_null(context)
        return
    }
    komaVectorInt8Result(context, value: values[0], elementStride: elementStride)
}

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

extension SQLiteKomaStore {
    func installVectorFunctions() throws {
        guard let db = connection.rawValue else {
            throw SQLiteKomaError.closed
        }

        for (argc, function) in [(Int32(1), sqliteKomaVectorInt8), (2, sqliteKomaVectorInt8Stride)] {
            let result = sqlite3_create_function_v2(
                db,
                "koma_vector_i8",
                argc,
                SQLITE_UTF8 | SQLITE_DETERMINISTIC,
                nil,
                function,
                nil,
                nil,
                nil
            )
            guard result == SQLITE_OK else {
                throw SQLiteKomaError.executionFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
}

public extension SQLiteKomaStore {
    /// Ranks records by cosine similarity of a vector column to `vector`, best first.
    ///
    /// Brute-force over the rows (exact, Swift-side) — ideal for a single-device store. For large
    /// corpora, pre-filter the candidate set (e.g. with `fullTextSearch`) and rank that. The
    /// column at `keyPath` must hold a vector encoded via `KomaVector.encode` — either precision;
    /// the scan detects `Float64` vs `Float32` per row from the blob length.
    ///
    /// The scan reads only `rowid` and the embedding blob, scoring each row straight from SQLite's
    /// bytes (no copy, no per-row allocation); only the top `limit` rows are hydrated into records.
    func nearest<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        on keyPath: KeyPath<Record.Columns, KomaColumn<Data>>,
        limit: Int
    ) async throws -> [(record: Record, similarity: Double)] {
        await waitForTransactionAccess()
        return try nearestRecords(type, to: vector, on: keyPath, limit: limit)
    }

    /// Creates an int8 quantized sidecar index for a vector column stored at `precision`.
    ///
    /// The index table is named `<table>_<column>_i8`. SQLite triggers keep it in sync for later
    /// inserts, updates, and deletes; creation also rebuilds it from existing rows.
    func createQuantizedVectorIndex<Record: KomaEntityRecord>(
        for type: Record.Type,
        on keyPath: KeyPath<Record.Columns, KomaColumn<Data>>,
        precision: KomaVectorPrecision = .float64
    ) async throws {
        await waitForTransactionAccess()

        let table = Record.komaTableName
        let column = Record.columns[keyPath: keyPath].name
        let indexTable = Self.quantizedVectorIndexTableName(table: table, column: column)

        let qTable = Self.quote(table)
        let qColumn = Self.quote(column)
        let qIndex = Self.quote(indexTable)
        let stride = precision.stride

        try execute(
            """
            CREATE TABLE IF NOT EXISTS \(qIndex) (
                rowid INTEGER PRIMARY KEY,
                code BLOB
            );

            CREATE TRIGGER IF NOT EXISTS \(Self.quote("\(indexTable)_ai")) AFTER INSERT ON \(qTable)
            WHEN new.\(qColumn) IS NOT NULL BEGIN
                INSERT INTO \(qIndex)(rowid, code) VALUES (new.rowid, koma_vector_i8(new.\(qColumn), \(stride)))
                ON CONFLICT(rowid) DO UPDATE SET code = excluded.code;
            END;

            CREATE TRIGGER IF NOT EXISTS \(Self.quote("\(indexTable)_au")) AFTER UPDATE OF \(qColumn) ON \(qTable) BEGIN
                DELETE FROM \(qIndex) WHERE rowid = old.rowid;
                INSERT INTO \(qIndex)(rowid, code)
                    SELECT new.rowid, koma_vector_i8(new.\(qColumn), \(stride))
                    WHERE new.\(qColumn) IS NOT NULL;
            END;

            CREATE TRIGGER IF NOT EXISTS \(Self.quote("\(indexTable)_ad")) AFTER DELETE ON \(qTable) BEGIN
                DELETE FROM \(qIndex) WHERE rowid = old.rowid;
            END;

            DELETE FROM \(qIndex);
            INSERT INTO \(qIndex)(rowid, code)
                SELECT rowid, koma_vector_i8(\(qColumn), \(stride)) FROM \(qTable)
                WHERE \(qColumn) IS NOT NULL;
            """
        )
    }

    /// Fast approximate recall over a trigger-maintained int8 sidecar, followed by exact
    /// full-precision reranking of the over-fetched candidates.
    ///
    /// Call `createQuantizedVectorIndex(for:on:precision:)` before using this path.
    func nearestQuantized<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        on keyPath: KeyPath<Record.Columns, KomaColumn<Data>>,
        limit: Int,
        overfetch: Int = 10
    ) async throws -> [(record: Record, similarity: Double)] {
        await waitForTransactionAccess()
        return try nearestQuantizedRecords(type, to: vector, on: keyPath, limit: limit, overfetch: overfetch)
    }

    /// Hybrid search: fuses FTS5 keyword recall with vector recall via Reciprocal Rank Fusion,
    /// returning the top `limit` records.
    ///
    /// Runs `fullTextSearch(matching:)` and vector recall each to `candidateLimit`, then fuses the
    /// two rankings by `idKeyPath`. Use `.quantized(overfetch:)` after creating a quantized vector
    /// index when you want faster vector recall with exact candidate reranking.
    func hybridSearch<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        matching query: String,
        near vector: [Double],
        on vectorKeyPath: KeyPath<Record.Columns, KomaColumn<Data>>,
        identifiedBy idKeyPath: KeyPath<Record, some Hashable>,
        limit: Int = 20,
        candidateLimit: Int = 50,
        k: Int = 60,
        vectorSearch: KomaVectorSearchMode = .exact
    ) async throws -> [Record] {
        await waitForTransactionAccess()

        let keyword = try fullTextRecords(type, matching: query, limit: candidateLimit)
        let semantic: [Record] = switch vectorSearch {
        case .exact:
            try nearestRecords(type, to: vector, on: vectorKeyPath, limit: candidateLimit).map(\.record)
        case let .quantized(overfetch):
            try nearestQuantizedRecords(
                type,
                to: vector,
                on: vectorKeyPath,
                limit: candidateLimit,
                overfetch: overfetch
            ).map(\.record)
        }
        let fused = KomaVector.fuse([keyword, semantic], by: idKeyPath, k: k)
        return Array(fused.prefix(limit))
    }
}

extension SQLiteKomaStore {
    func nearestRecords<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        on keyPath: KeyPath<Record.Columns, KomaColumn<Data>>,
        limit: Int
    ) throws -> [(record: Record, similarity: Double)] {
        guard limit > 0 else { return [] }

        let table = Self.quote(Record.komaTableName)

        // 1. Score in place over a lean projection (rowid + embedding blob), keeping the top `limit`.
        let winners = try scoreVectorColumn(
            table: table,
            column: Self.quote(Record.columns[keyPath: keyPath].name),
            to: vector,
            limit: limit
        )
        guard !winners.isEmpty else { return [] }

        // 2. Hydrate only the winners into full records, ordered to match (CASE maps rowid -> rank).
        let ids = winners.map { String($0.rowid) }.joined(separator: ", ")
        let ranking = winners.enumerated()
            .map { "WHEN \($0.element.rowid) THEN \($0.offset)" }
            .joined(separator: " ")
        let columns = Self.quotedSelectColumnList(Record.komaColumns, qualifier: nil)
        let records = try rawRecords(
            Record.self,
            """
            SELECT \(columns) FROM \(table)
            WHERE rowid IN (\(ids))
            ORDER BY CASE rowid \(ranking) END
            """
        )
        return zip(records, winners).map { (record: $0, similarity: $1.similarity) }
    }

    func nearestQuantizedRecords<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        on keyPath: KeyPath<Record.Columns, KomaColumn<Data>>,
        limit: Int,
        overfetch: Int
    ) throws -> [(record: Record, similarity: Double)] {
        guard limit > 0, overfetch > 0 else { return [] }

        let tableName = Record.komaTableName
        let columnName = Record.columns[keyPath: keyPath].name
        let table = Self.quote(tableName)
        let column = Self.quote(columnName)
        let indexTable = Self.quote(Self.quantizedVectorIndexTableName(table: tableName, column: columnName))

        let winners = try scoreQuantizedVectorIndex(
            selection: (indexTable: indexTable, baseTable: table, column: column),
            to: vector,
            limit: limit,
            overfetch: overfetch
        )
        guard !winners.isEmpty else { return [] }

        let ids = winners.map { String($0.rowid) }.joined(separator: ", ")
        let ranking = winners.enumerated()
            .map { "WHEN \($0.element.rowid) THEN \($0.offset)" }
            .joined(separator: " ")
        let columns = Self.quotedSelectColumnList(Record.komaColumns, qualifier: nil)
        let records = try rawRecords(
            Record.self,
            """
            SELECT \(columns) FROM \(table)
            WHERE rowid IN (\(ids))
            ORDER BY CASE rowid \(ranking) END
            """
        )
        return zip(records, winners).map { (record: $0, similarity: $1.similarity) }
    }

    /// Streams `(rowid, embedding)` from `table.column` and returns the `limit` rows whose vector is
    /// most cosine-similar to `query`. Each blob is scored directly off SQLite's row buffer — no
    /// `Data` copy and no `[Double]` is allocated per row; a bounded min-heap keeps the top `limit`
    /// so the scan never sorts the whole table. `table`/`column` must be pre-quoted.
    func scoreVectorColumn(
        table: String,
        column: String,
        to query: [Double],
        limit: Int
    ) throws -> [(rowid: Int64, similarity: Double)] {
        let float64Bytes = query.count * MemoryLayout<Double>.stride
        let float32Bytes = query.count * MemoryLayout<Float>.stride
        // The query's own norm is constant across rows, so hoist it out of the scan.
        let queryNorm = query.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard queryNorm > 0 else { return [] }

        return try query.withUnsafeBufferPointer { queryBuffer in
            try withStatement("SELECT rowid, \(column) FROM \(table)") { statement in
                var top = VectorTopK<Double>(limit)
                while true {
                    switch sqlite3_step(statement) {
                    case SQLITE_ROW:
                        guard let bytes = sqlite3_column_blob(statement, 1) else { continue }
                        let scored: (dot: Double, norm: Double)
                        switch Int(sqlite3_column_bytes(statement, 1)) {
                        case float64Bytes:
                            scored = Self.dotAndNorm(queryBuffer, float64: bytes)
                        case float32Bytes:
                            scored = Self.dotAndNorm(queryBuffer, float32: bytes)
                        default:
                            continue // skip rows whose vector is absent or a different dimension
                        }
                        let magnitude = queryNorm * scored.norm.squareRoot()
                        top.insert(
                            magnitude == 0 ? 0 : scored.dot / magnitude,
                            rowid: sqlite3_column_int64(statement, 0)
                        )
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
    func scoreQuantizedVectorIndex(
        selection: (indexTable: String, baseTable: String, column: String),
        to query: [Double],
        limit: Int,
        overfetch: Int
    ) throws -> [(rowid: Int64, similarity: Double)] {
        let queryCode = KomaVector.encodeInt8(query)
        let dimension = queryCode.count
        guard dimension > 0 else { return [] }

        let candidateLimit = max(limit, limit * overfetch)
        let candidates = try queryCode.withUnsafeBytes { raw -> [Int64] in
            let queryCodes = raw.bindMemory(to: Int8.self)
            return try withStatement("SELECT rowid, code FROM \(selection.indexTable)") { statement in
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
            try withStatement("SELECT rowid, \(selection.column) FROM \(selection.baseTable) WHERE rowid IN (\(ids))") { statement in
                var top = VectorTopK<Double>(limit)
                while true {
                    switch sqlite3_step(statement) {
                    case SQLITE_ROW:
                        guard let bytes = sqlite3_column_blob(statement, 1) else { continue }
                        let scored: (dot: Double, norm: Double)
                        switch Int(sqlite3_column_bytes(statement, 1)) {
                        case float64Bytes:
                            scored = Self.dotAndNorm(queryBuffer, float64: bytes)
                        case float32Bytes:
                            scored = Self.dotAndNorm(queryBuffer, float32: bytes)
                        default:
                            continue
                        }
                        let magnitude = queryNorm * scored.norm.squareRoot()
                        top.insert(
                            magnitude == 0 ? 0 : scored.dot / magnitude,
                            rowid: sqlite3_column_int64(statement, 0)
                        )
                    case SQLITE_DONE:
                        return top.sortedDescending().map { (rowid: $0.rowid, similarity: $0.score) }
                    default:
                        throw Self.stepError(statement)
                    }
                }
            }
        }
    }

    static func quantizedVectorIndexTableName(table: String, column: String) -> String {
        "\(table)_\(column)_i8"
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
