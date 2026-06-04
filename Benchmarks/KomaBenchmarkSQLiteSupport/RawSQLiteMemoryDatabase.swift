import CKomaSQLite
import Foundation

/// Hand-written SQLite (C API) implementation of FTS5 keyword search, brute-force vector search,
/// and hybrid (RRF) fusion — the zero-framework floor for the `koma.sqlite.*` / `grdb.sqlite.*`
/// memory benchmarks. Same algorithm as Koma's store: an in-place `rowid + embedding` scan
/// (`loadUnaligned`, no per-row copy), top-k, then hydrate only the winners.
///
/// @unchecked Sendable: a single connection driven sequentially, so a populated instance can be
/// cached in BenchmarkFixtureCache and reused across measured iterations.
public final class RawSQLiteMemoryDatabase: @unchecked Sendable {
    private var connection: OpaquePointer?

    public init(path: String) throws {
        guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
        else {
            throw RawSQLiteMemoryError.openFailed(errorMessage)
        }
        try execute("PRAGMA journal_mode = WAL")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS memories (
                id TEXT PRIMARY KEY NOT NULL,
                content TEXT NOT NULL,
                embedding BLOB NOT NULL
            )
            """
        )
        try execute("CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(content, content='memories', content_rowid='rowid')")
        try execute(
            """
            CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
                INSERT INTO memories_fts(rowid, content) VALUES (new.rowid, new.content);
            END
            """
        )
    }

    deinit {
        if let connection {
            sqlite3_close(connection)
        }
    }

    public func populate(count: Int, content: (Int) -> String, embedding: (Int) -> Data) throws {
        let statement = try prepare("INSERT INTO memories (id, content, embedding) VALUES (?, ?, ?)")
        defer { sqlite3_finalize(statement) }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for index in 0 ..< count {
                sqlite3_bind_text(statement, 1, "\(index)", -1, rawMemoryTransient)
                sqlite3_bind_text(statement, 2, content(index), -1, rawMemoryTransient)
                let blob = embedding(index)
                blob.withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, 3, raw.baseAddress, Int32(raw.count), rawMemoryTransient)
                }
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw RawSQLiteMemoryError.executionFailed(errorMessage)
                }
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// FTS5 keyword search, bm25-ranked, materializing the matching rows (id + content + embedding).
    public func fullTextSearch(_ query: String, limit: Int) throws -> [RawMemoryRow] {
        let statement = try prepare(
            """
            SELECT m.id, m.content, m.embedding
            FROM memories AS m
            JOIN memories_fts ON memories_fts.rowid = m.rowid
            WHERE memories_fts MATCH ?
            ORDER BY memories_fts.rank
            LIMIT ?
            """
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, query, -1, rawMemoryTransient)
        sqlite3_bind_int64(statement, 2, Int64(limit))

        var rows: [RawMemoryRow] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append(row(from: statement))
        }
        return rows
    }

    /// Brute-force cosine over every row, returning the top `limit` hydrated rows by similarity.
    public func nearest(to query: [Double], limit: Int) throws -> [(row: RawMemoryRow, similarity: Double)] {
        guard limit > 0 else { return [] }
        let stride = MemoryLayout<Double>.stride
        let expectedBytes = query.count * stride
        let queryNorm = query.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard queryNorm > 0 else { return [] }

        // 1. In-place scan: score rowid + embedding straight off SQLite's row buffer.
        let scan = try prepare("SELECT rowid, embedding FROM memories")
        defer { sqlite3_finalize(scan) }
        var scored: [(rowid: Int64, similarity: Double)] = []
        while sqlite3_step(scan) == SQLITE_ROW {
            let byteCount = Int(sqlite3_column_bytes(scan, 1))
            guard byteCount == expectedBytes, let bytes = sqlite3_column_blob(scan, 1) else { continue }
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
            scored.append((sqlite3_column_int64(scan, 0), magnitude == 0 ? 0 : dot / magnitude))
        }

        let winners = Array(scored.sorted { $0.similarity > $1.similarity }.prefix(limit))
        guard !winners.isEmpty else { return [] }

        // 2. Hydrate only the winners, ordered to match (CASE maps rowid -> rank).
        let ids = winners.map { String($0.rowid) }.joined(separator: ", ")
        let ranking = winners.enumerated()
            .map { "WHEN \($0.element.rowid) THEN \($0.offset)" }
            .joined(separator: " ")
        let hydrate = try prepare(
            "SELECT id, content, embedding FROM memories WHERE rowid IN (\(ids)) ORDER BY CASE rowid \(ranking) END"
        )
        defer { sqlite3_finalize(hydrate) }
        var rows: [RawMemoryRow] = []
        while sqlite3_step(hydrate) == SQLITE_ROW {
            rows.append(row(from: hydrate))
        }
        return zip(rows, winners).map { (row: $0, similarity: $1.similarity) }
    }

    /// Hybrid: fuse FTS5 keyword recall and vector recall (each to `candidateLimit`) via RRF.
    public func hybridSearch(matching query: String, near vector: [Double], limit: Int, candidateLimit: Int = 50) throws -> [RawMemoryRow] {
        let keyword = try fullTextSearch(query, limit: candidateLimit)
        let semantic = try nearest(to: vector, limit: candidateLimit).map(\.row)

        var scores: [String: Double] = [:]
        var firstSeen: [String: RawMemoryRow] = [:]
        for ranking in [keyword, semantic] {
            for (offset, row) in ranking.enumerated() {
                scores[row.id, default: 0] += 1.0 / Double(60 + offset + 1)
                if firstSeen[row.id] == nil {
                    firstSeen[row.id] = row
                }
            }
        }
        let fused = scores.sorted { $0.value > $1.value }.compactMap { firstSeen[$0.key] }
        return Array(fused.prefix(limit))
    }

    /// Builds an int8 sidecar table holding one quantized code per row, keyed by the main table's
    /// rowid (rows are inserted 0..<count, so rowid == index + 1). The compact codes are what the
    /// quantized scan reads — 1 byte/dim vs 8 for the Float64 embedding.
    public func buildInt8Index(count: Int, code: (Int) -> Data) throws {
        try execute("CREATE TABLE IF NOT EXISTS memories_i8 (rowid INTEGER PRIMARY KEY, code BLOB NOT NULL)")
        let statement = try prepare("INSERT INTO memories_i8 (rowid, code) VALUES (?, ?)")
        defer { sqlite3_finalize(statement) }

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            for index in 0 ..< count {
                sqlite3_bind_int64(statement, 1, Int64(index + 1))
                code(index).withUnsafeBytes { raw in
                    sqlite3_bind_blob(statement, 2, raw.baseAddress, Int32(raw.count), rawMemoryTransient)
                }
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw RawSQLiteMemoryError.executionFailed(errorMessage)
                }
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Quantized nearest: scan the compact int8 sidecar (integer dot ≈ cosine ranking) for the top
    /// `limit * overfetch` candidates, then rerank those with exact Float64 cosine for the top-k.
    public func nearestQuantized(queryCode: Data, query: [Double], limit: Int, overfetch: Int) throws -> [(
        row: RawMemoryRow,
        similarity: Double
    )] {
        guard limit > 0 else { return [] }
        let queryCodes = queryCode.withUnsafeBytes { Array($0.bindMemory(to: Int8.self)) }
        let dimension = queryCodes.count

        // 1. int8 pre-filter scan over the sidecar — integer dot product, read in place.
        let scan = try prepare("SELECT rowid, code FROM memories_i8")
        defer { sqlite3_finalize(scan) }
        var scored: [(rowid: Int64, score: Int)] = []
        while sqlite3_step(scan) == SQLITE_ROW {
            guard Int(sqlite3_column_bytes(scan, 1)) == dimension,
                  let bytes = sqlite3_column_blob(scan, 1) else { continue }
            let codes = bytes.assumingMemoryBound(to: Int8.self)
            var dot = 0
            for index in 0 ..< dimension {
                dot += Int(queryCodes[index]) * Int(codes[index])
            }
            scored.append((sqlite3_column_int64(scan, 0), dot))
        }

        let candidates = scored.sorted { $0.score > $1.score }.prefix(limit * overfetch).map(\.rowid)
        guard !candidates.isEmpty else { return [] }

        // 2. Rerank candidates with exact full-precision cosine.
        let queryNorm = query.reduce(0) { $0 + $1 * $1 }.squareRoot()
        let ids = candidates.map(String.init).joined(separator: ", ")
        let rerank = try prepare("SELECT id, content, embedding FROM memories WHERE rowid IN (\(ids))")
        defer { sqlite3_finalize(rerank) }
        var reranked: [(row: RawMemoryRow, similarity: Double)] = []
        while sqlite3_step(rerank) == SQLITE_ROW {
            let row = row(from: rerank)
            reranked.append((row, exactCosine(query, queryNorm: queryNorm, blob: row.embedding)))
        }
        return Array(reranked.sorted { $0.similarity > $1.similarity }.prefix(limit))
    }

    private func exactCosine(_ query: [Double], queryNorm: Double, blob: Data) -> Double {
        blob.withUnsafeBytes { raw in
            let values = raw.bindMemory(to: Double.self)
            guard values.count == query.count, queryNorm > 0 else { return 0 }
            var dot = 0.0
            var normB = 0.0
            for index in query.indices {
                dot += query[index] * values[index]
                normB += values[index] * values[index]
            }
            let magnitude = queryNorm * normB.squareRoot()
            return magnitude == 0 ? 0 : dot / magnitude
        }
    }

    private func row(from statement: OpaquePointer) -> RawMemoryRow {
        let id = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? ""
        let content = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
        let count = Int(sqlite3_column_bytes(statement, 2))
        let embedding = sqlite3_column_blob(statement, 2).map { Data(bytes: $0, count: count) } ?? Data()
        return RawMemoryRow(id: id, content: content, embedding: embedding)
    }

    private var errorMessage: String {
        guard let connection, let message = sqlite3_errmsg(connection) else { return "Unknown SQLite error." }
        return String(cString: message)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(connection, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(error)
            throw RawSQLiteMemoryError.executionFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw RawSQLiteMemoryError.executionFailed(errorMessage)
        }
        return statement
    }
}

public struct RawMemoryRow: Sendable {
    public let id: String
    public let content: String
    public let embedding: Data
}

enum RawSQLiteMemoryError: Error {
    case openFailed(String)
    case executionFailed(String)
}

private let rawMemoryTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
