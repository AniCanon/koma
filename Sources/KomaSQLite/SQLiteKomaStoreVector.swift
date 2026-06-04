import CKomaSQLite
import Foundation
import Koma

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
        let records = try rawQuery(
            Record.self,
            """
            SELECT \(columns) FROM \(table)
            WHERE rowid IN (\(ids))
            ORDER BY CASE rowid \(ranking) END
            """
        )
        return zip(records, winners).map { (record: $0, similarity: $1.similarity) }
    }

    /// Hybrid search: fuses FTS5 keyword recall with vector (cosine) recall via Reciprocal
    /// Rank Fusion, returning the top `limit` records.
    ///
    /// Runs `fullTextSearch(matching:)` and `nearest(to:on:)` each to `candidateLimit`, then
    /// fuses the two rankings by `idKeyPath`. Requires `createFullTextIndex` to have been set up
    /// for the text column and the vector column to hold `KomaVector.encode` output.
    func hybridSearch<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        matching query: String,
        near vector: [Double],
        on vectorKeyPath: KeyPath<Record.Columns, KomaColumn<Data>>,
        identifiedBy idKeyPath: KeyPath<Record, some Hashable>,
        limit: Int = 20,
        candidateLimit: Int = 50,
        k: Int = 60
    ) async throws -> [Record] {
        let keyword = try fullTextSearch(type, matching: query, limit: candidateLimit)
        let semantic = try await nearest(type, to: vector, on: vectorKeyPath, limit: candidateLimit).map(\.record)
        let fused = KomaVector.fuse([keyword, semantic], by: idKeyPath, k: k)
        return Array(fused.prefix(limit))
    }
}

extension SQLiteKomaStore {
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
}
