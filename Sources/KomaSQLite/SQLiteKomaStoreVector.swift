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

extension SQLiteKomaStore {
    static func installVectorFunctions(on db: OpaquePointer) throws {
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
    ///
    /// Pass `assumeNormalized: true` when the stored vectors and the query are L2-normalized
    /// (most embedding models emit normalized vectors): cosine reduces to the dot product and
    /// the scan skips per-row norm accumulation — roughly half the arithmetic.
    nonisolated func nearest<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        on keyPath: KeyPath<Record.Columns, KomaColumn<Data>>,
        limit: Int,
        assumeNormalized: Bool = false
    ) async throws -> [(record: Record, similarity: Double)] {
        let column = Record.columns[keyPath: keyPath].name
        if let readPool, SQLiteKomaTransactionContext.id == nil {
            return try await readPool.withConnection { access in
                try Self.nearestRecords(
                    type,
                    to: vector,
                    column: column,
                    limit: limit,
                    assumeNormalized: assumeNormalized,
                    access: access
                )
            }
        }
        return try await nearestOnWriter(
            type,
            to: vector,
            column: column,
            limit: limit,
            assumeNormalized: assumeNormalized
        )
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
    nonisolated func nearestQuantized<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        on keyPath: KeyPath<Record.Columns, KomaColumn<Data>>,
        limit: Int,
        overfetch: Int = 10,
        assumeNormalized: Bool = false
    ) async throws -> [(record: Record, similarity: Double)] {
        let column = Record.columns[keyPath: keyPath].name
        if let readPool, SQLiteKomaTransactionContext.id == nil {
            return try await readPool.withConnection { access in
                try Self.nearestQuantizedRecords(
                    type,
                    to: vector,
                    column: column,
                    limit: limit,
                    overfetch: overfetch,
                    assumeNormalized: assumeNormalized,
                    access: access
                )
            }
        }
        return try await nearestQuantizedOnWriter(
            type,
            to: vector,
            column: column,
            limit: limit,
            overfetch: overfetch,
            assumeNormalized: assumeNormalized
        )
    }

    /// Hybrid search: fuses FTS5 keyword recall with vector recall via Reciprocal Rank Fusion,
    /// returning the top `limit` records.
    ///
    /// Runs `fullTextSearch(matching:)` and vector recall each to `candidateLimit`, then fuses the
    /// two rankings by `idKeyPath`. Use `.quantized(overfetch:)` after creating a quantized vector
    /// index when you want faster vector recall with exact candidate reranking. With the read pool
    /// available, the keyword and vector legs run concurrently on separate read connections.
    nonisolated func hybridSearch<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        matching query: String,
        near vector: [Double],
        on vectorKeyPath: KeyPath<Record.Columns, KomaColumn<Data>>,
        identifiedBy idKeyPath: KeyPath<Record, some Hashable>,
        limit: Int = 20,
        candidateLimit: Int = 50,
        k: Int = 60,
        vectorSearch: KomaVectorSearchMode = .exact,
        assumeNormalized: Bool = false
    ) async throws -> [Record] {
        let column = Record.columns[keyPath: vectorKeyPath].name

        if let readPool, SQLiteKomaTransactionContext.id == nil {
            async let keywordRecall = readPool.withConnection { access in
                try Self.fullTextRecords(type, matching: query, limit: candidateLimit, access: access)
            }
            async let semanticRecall = readPool.withConnection { access -> [Record] in
                switch vectorSearch {
                case .exact:
                    try Self.nearestRecords(
                        type,
                        to: vector,
                        column: column,
                        limit: candidateLimit,
                        assumeNormalized: assumeNormalized,
                        access: access
                    ).map(\.record)
                case let .quantized(overfetch):
                    try Self.nearestQuantizedRecords(
                        type,
                        to: vector,
                        column: column,
                        limit: candidateLimit,
                        overfetch: overfetch,
                        assumeNormalized: assumeNormalized,
                        access: access
                    ).map(\.record)
                }
            }
            let fused = try await KomaVector.fuse([keywordRecall, semanticRecall], by: idKeyPath, k: k)
            return Array(fused.prefix(limit))
        }

        // Fusion happens out here so the non-Sendable key path never crosses into the actor.
        let (keyword, semantic) = try await hybridRecallOnWriter(
            type,
            matching: query,
            near: vector,
            column: column,
            candidateLimit: candidateLimit,
            vectorSearch: vectorSearch,
            assumeNormalized: assumeNormalized
        )
        let fused = KomaVector.fuse([keyword, semantic], by: idKeyPath, k: k)
        return Array(fused.prefix(limit))
    }
}

extension SQLiteKomaStore {
    func nearestOnWriter<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        column: String,
        limit: Int,
        assumeNormalized: Bool
    ) async throws -> [(record: Record, similarity: Double)] {
        await waitForTransactionAccess()
        return try Self.nearestRecords(
            type,
            to: vector,
            column: column,
            limit: limit,
            assumeNormalized: assumeNormalized,
            access: writerAccess
        )
    }

    func nearestQuantizedOnWriter<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        column: String,
        limit: Int,
        overfetch: Int = 10,
        assumeNormalized: Bool = false
    ) async throws -> [(record: Record, similarity: Double)] {
        await waitForTransactionAccess()
        return try Self.nearestQuantizedRecords(
            type,
            to: vector,
            column: column,
            limit: limit,
            overfetch: overfetch,
            assumeNormalized: assumeNormalized,
            access: writerAccess
        )
    }

    func hybridRecallOnWriter<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        matching query: String,
        near vector: [Double],
        column: String,
        candidateLimit: Int,
        vectorSearch: KomaVectorSearchMode = .exact,
        assumeNormalized: Bool = false
    ) async throws -> (keyword: [Record], semantic: [Record]) {
        await waitForTransactionAccess()

        let access = try writerAccess
        let keyword = try Self.fullTextRecords(type, matching: query, limit: candidateLimit, access: access)
        let semantic: [Record] = switch vectorSearch {
        case .exact:
            try Self.nearestRecords(
                type,
                to: vector,
                column: column,
                limit: candidateLimit,
                assumeNormalized: assumeNormalized,
                access: access
            ).map(\.record)
        case let .quantized(overfetch):
            try Self.nearestQuantizedRecords(
                type,
                to: vector,
                column: column,
                limit: candidateLimit,
                overfetch: overfetch,
                assumeNormalized: assumeNormalized,
                access: access
            ).map(\.record)
        }
        return (keyword, semantic)
    }

    static func nearestRecords<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        column columnName: String,
        limit: Int,
        assumeNormalized: Bool = false,
        access: SQLiteDatabaseAccess
    ) throws -> [(record: Record, similarity: Double)] {
        guard limit > 0 else { return [] }

        let table = Self.quote(Record.komaTableName)

        // 1. Score in place over a lean projection (rowid + embedding blob), keeping the top `limit`.
        let winners = try scoreVectorColumn(
            table: table,
            column: Self.quote(columnName),
            to: vector,
            limit: limit,
            assumeNormalized: assumeNormalized,
            access: access
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
            """,
            access: access
        )
        return zip(records, winners).map { (record: $0, similarity: $1.similarity) }
    }

    static func nearestQuantizedRecords<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        to vector: [Double],
        column columnName: String,
        limit: Int,
        overfetch: Int = 10,
        assumeNormalized: Bool = false,
        access: SQLiteDatabaseAccess
    ) throws -> [(record: Record, similarity: Double)] {
        guard limit > 0, overfetch > 0 else { return [] }

        let tableName = Record.komaTableName
        let table = Self.quote(tableName)
        let column = Self.quote(columnName)
        let indexTable = Self.quote(Self.quantizedVectorIndexTableName(table: tableName, column: columnName))

        let winners = try scoreQuantizedVectorIndex(
            selection: (indexTable: indexTable, baseTable: table, column: column),
            to: vector,
            limit: limit,
            overfetch: overfetch,
            assumeNormalized: assumeNormalized,
            access: access
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
            """,
            access: access
        )
        return zip(records, winners).map { (record: $0, similarity: $1.similarity) }
    }

    static func quantizedVectorIndexTableName(table: String, column: String) -> String {
        "\(table)_\(column)_i8"
    }
}
