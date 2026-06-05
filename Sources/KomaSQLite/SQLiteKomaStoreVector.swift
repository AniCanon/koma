import CKomaSQLite
import Foundation
import Koma

private let sqliteKomaVectorInt8: @convention(c) (
    OpaquePointer?,
    Int32,
    UnsafeMutablePointer<OpaquePointer?>?
) -> Void = { context, argc, values in
    guard argc == 1,
          let values,
          let value = values[0],
          sqlite3_value_type(value) == SQLITE_BLOB
    else {
        sqlite3_result_null(context)
        return
    }

    let stride = MemoryLayout<Double>.stride
    let byteCount = Int(sqlite3_value_bytes(value))
    guard byteCount.isMultiple(of: stride) else {
        sqlite3_result_null(context)
        return
    }

    let dimension = byteCount / stride
    guard dimension > 0 else {
        sqlite3_result_blob(context, nil, 0, SQLITE_TRANSIENT)
        return
    }

    guard let bytes = sqlite3_value_blob(value) else {
        sqlite3_result_null(context)
        return
    }

    var norm = 0.0
    var offset = 0
    for _ in 0 ..< dimension {
        let component = bytes.loadUnaligned(fromByteOffset: offset, as: Double.self)
        norm += component * component
        offset += stride
    }

    var codes = [Int8](repeating: 0, count: dimension)
    if norm > 0 {
        let scale = 127.0 / norm.squareRoot()
        offset = 0
        for index in 0 ..< dimension {
            let component = bytes.loadUnaligned(fromByteOffset: offset, as: Double.self)
            codes[index] = Int8(max(-127, min(127, (component * scale).rounded())))
            offset += stride
        }
    }

    codes.withUnsafeBytes { raw in
        sqlite3_result_blob(context, raw.baseAddress, Int32(raw.count), SQLITE_TRANSIENT)
    }
}

extension SQLiteKomaStore {
    func installVectorFunctions() throws {
        guard let db = connection.rawValue else {
            throw SQLiteKomaError.closed
        }

        let result = sqlite3_create_function_v2(
            db,
            "koma_vector_i8",
            1,
            SQLITE_UTF8 | SQLITE_DETERMINISTIC,
            nil,
            sqliteKomaVectorInt8,
            nil,
            nil,
            nil
        )
        guard result == SQLITE_OK else {
            throw SQLiteKomaError.executionFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}

public extension SQLiteKomaStore {
    /// Ranks records by cosine similarity of a `Float64` vector column to `vector`, best first.
    ///
    /// Brute-force over the rows (exact, Swift-side) — ideal for a single-device store. For large
    /// corpora, pre-filter the candidate set (e.g. with `fullTextSearch`) and rank that. The
    /// column at `keyPath` must hold a vector encoded via `KomaVector.encode`.
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

    /// Creates an int8 quantized sidecar index for a `Float64` vector column.
    ///
    /// The index table is named `<table>_<column>_i8`. SQLite triggers keep it in sync for later
    /// inserts, updates, and deletes; creation also rebuilds it from existing rows.
    func createQuantizedVectorIndex<Record: KomaEntityRecord>(
        for type: Record.Type,
        on keyPath: KeyPath<Record.Columns, KomaColumn<Data>>
    ) async throws {
        await waitForTransactionAccess()

        let table = Record.komaTableName
        let column = Record.columns[keyPath: keyPath].name
        let indexTable = Self.quantizedVectorIndexTableName(table: table, column: column)

        let qTable = Self.quote(table)
        let qColumn = Self.quote(column)
        let qIndex = Self.quote(indexTable)

        try execute(
            """
            CREATE TABLE IF NOT EXISTS \(qIndex) (
                rowid INTEGER PRIMARY KEY,
                code BLOB
            );

            CREATE TRIGGER IF NOT EXISTS \(Self.quote("\(indexTable)_ai")) AFTER INSERT ON \(qTable)
            WHEN new.\(qColumn) IS NOT NULL BEGIN
                INSERT INTO \(qIndex)(rowid, code) VALUES (new.rowid, koma_vector_i8(new.\(qColumn)))
                ON CONFLICT(rowid) DO UPDATE SET code = excluded.code;
            END;

            CREATE TRIGGER IF NOT EXISTS \(Self.quote("\(indexTable)_au")) AFTER UPDATE OF \(qColumn) ON \(qTable) BEGIN
                DELETE FROM \(qIndex) WHERE rowid = old.rowid;
                INSERT INTO \(qIndex)(rowid, code)
                    SELECT new.rowid, koma_vector_i8(new.\(qColumn))
                    WHERE new.\(qColumn) IS NOT NULL;
            END;

            CREATE TRIGGER IF NOT EXISTS \(Self.quote("\(indexTable)_ad")) AFTER DELETE ON \(qTable) BEGIN
                DELETE FROM \(qIndex) WHERE rowid = old.rowid;
            END;

            DELETE FROM \(qIndex);
            INSERT INTO \(qIndex)(rowid, code)
                SELECT rowid, koma_vector_i8(\(qColumn)) FROM \(qTable)
                WHERE \(qColumn) IS NOT NULL;
            """
        )
    }

    /// Fast approximate recall over a trigger-maintained int8 sidecar, followed by exact
    /// full-precision reranking of the over-fetched candidates.
    ///
    /// Call `createQuantizedVectorIndex(for:on:)` before using this path.
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
        let semantic: [Record]
        switch vectorSearch {
        case .exact:
            semantic = try nearestRecords(type, to: vector, on: vectorKeyPath, limit: candidateLimit).map(\.record)
        case let .quantized(overfetch):
            semantic = try nearestQuantizedRecords(
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
            indexTable: indexTable,
            baseTable: table,
            column: column,
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
    /// `Data` copy and no `[Double]` is allocated per row. `table`/`column` must be pre-quoted.
    func scoreVectorColumn(
        table: String,
        column: String,
        to query: [Double],
        limit: Int
    ) throws -> [(rowid: Int64, similarity: Double)] {
        let stride = MemoryLayout<Double>.stride
        let expectedBytes = query.count * stride
        // The query's own norm is constant across rows, so hoist it out of the scan. The cosine is
        // then inlined (rather than calling `KomaVector.cosine`) to read each row's bytes in place
        // with `loadUnaligned` — no `Data` wrapper and no `[Double]` allocated per row.
        let queryNorm = query.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard queryNorm > 0 else { return [] }

        return try withStatement("SELECT rowid, \(column) FROM \(table)") { statement in
            var scored: [(rowid: Int64, similarity: Double)] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    let byteCount = Int(sqlite3_column_bytes(statement, 1))
                    guard byteCount == expectedBytes, let bytes = sqlite3_column_blob(statement, 1) else {
                        continue // skip rows whose vector is absent or a different dimension
                    }
                    var dot = 0.0
                    var normB = 0.0
                    var offset = 0
                    for index in query.indices {
                        let value = bytes.loadUnaligned(fromByteOffset: offset, as: Double.self)
                        dot += query[index] * value
                        normB += value * value
                        offset += stride
                    }
                    let magnitude = queryNorm * normB.squareRoot()
                    let similarity = magnitude == 0 ? 0 : dot / magnitude
                    scored.append((sqlite3_column_int64(statement, 0), similarity))
                case SQLITE_DONE:
                    return Array(scored.sorted { $0.similarity > $1.similarity }.prefix(limit))
                default:
                    throw Self.stepError(statement)
                }
            }
        }
    }

    /// Scans the int8 sidecar for candidates, then reranks those candidates with exact Float64
    /// cosine using the base table's original embedding blob. Inputs must be pre-quoted.
    func scoreQuantizedVectorIndex(
        indexTable: String,
        baseTable: String,
        column: String,
        to query: [Double],
        limit: Int,
        overfetch: Int
    ) throws -> [(rowid: Int64, similarity: Double)] {
        let queryCode = KomaVector.encodeInt8(query)
        let queryCodes = queryCode.withUnsafeBytes { Array($0.bindMemory(to: Int8.self)) }
        let dimension = queryCodes.count
        guard dimension > 0 else { return [] }

        let candidateLimit = max(limit, limit * overfetch)
        let candidates = try withStatement("SELECT rowid, code FROM \(indexTable)") { statement in
            var scored: [(rowid: Int64, score: Int)] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    let byteCount = Int(sqlite3_column_bytes(statement, 1))
                    guard byteCount == dimension, let bytes = sqlite3_column_blob(statement, 1) else {
                        continue
                    }
                    let codes = bytes.assumingMemoryBound(to: Int8.self)
                    var dot = 0
                    for index in 0 ..< dimension {
                        dot += Int(queryCodes[index]) * Int(codes[index])
                    }
                    scored.append((sqlite3_column_int64(statement, 0), dot))
                case SQLITE_DONE:
                    return Array(scored.sorted { $0.score > $1.score }.prefix(candidateLimit).map(\.rowid))
                default:
                    throw Self.stepError(statement)
                }
            }
        }
        guard !candidates.isEmpty else { return [] }

        let queryNorm = query.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard queryNorm > 0 else { return [] }

        let ids = candidates.map(String.init).joined(separator: ", ")
        return try withStatement("SELECT rowid, \(column) FROM \(baseTable) WHERE rowid IN (\(ids))") { statement in
            var reranked: [(rowid: Int64, similarity: Double)] = []
            while true {
                switch sqlite3_step(statement) {
                case SQLITE_ROW:
                    let byteCount = Int(sqlite3_column_bytes(statement, 1))
                    guard byteCount == query.count * MemoryLayout<Double>.stride,
                          let bytes = sqlite3_column_blob(statement, 1)
                    else {
                        continue
                    }
                    let similarity = Self.cosine(query, queryNorm: queryNorm, bytes: bytes)
                    reranked.append((sqlite3_column_int64(statement, 0), similarity))
                case SQLITE_DONE:
                    return Array(reranked.sorted { $0.similarity > $1.similarity }.prefix(limit))
                default:
                    throw Self.stepError(statement)
                }
            }
        }
    }

    static func quantizedVectorIndexTableName(table: String, column: String) -> String {
        "\(table)_\(column)_i8"
    }

    private static func cosine(_ query: [Double], queryNorm: Double, bytes: UnsafeRawPointer) -> Double {
        var dot = 0.0
        var normB = 0.0
        var offset = 0
        let stride = MemoryLayout<Double>.stride
        for index in query.indices {
            let value = bytes.loadUnaligned(fromByteOffset: offset, as: Double.self)
            dot += query[index] * value
            normB += value * value
            offset += stride
        }
        let magnitude = queryNorm * normB.squareRoot()
        return magnitude == 0 ? 0 : dot / magnitude
    }
}
