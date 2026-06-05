import CKomaSQLite
import Foundation
import Koma

public extension SQLiteKomaStore {
    /// Creates an FTS5 full-text index over a text column of `Record`, kept in sync with the
    /// base table via triggers. Idempotent, but it rebuilds from existing rows, so prefer calling
    /// it during setup or migrations rather than on a hot path.
    ///
    /// The index is an external-content FTS5 table named `<table>_fts`; the base table remains
    /// the source of truth. Query it with `fullTextSearch(_:matching:limit:)`.
    func createFullTextIndex<Record: KomaEntityRecord>(
        for type: Record.Type,
        indexing keyPath: KeyPath<Record.Columns, KomaColumn<some Any>>
    ) async throws {
        await waitForTransactionAccess()

        let table = Record.komaTableName
        let ftsTable = "\(table)_fts"
        let column = Record.columns[keyPath: keyPath].name

        let qTable = Self.quote(table)
        let qFTS = Self.quote(ftsTable)
        let qColumn = Self.quote(column)
        let tableLiteral = Self.stringLiteral(table)

        // Identifying the FTS table by its own name inside an INSERT issues FTS5's special
        // 'delete' command, which is how external-content indexes are kept consistent.
        try execute(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS \(qFTS)
                USING fts5(\(qColumn), content=\(tableLiteral), content_rowid='rowid');

            CREATE TRIGGER IF NOT EXISTS \(Self.quote("\(ftsTable)_ai")) AFTER INSERT ON \(qTable) BEGIN
                INSERT INTO \(qFTS)(rowid, \(qColumn)) VALUES (new.rowid, new.\(qColumn));
            END;

            CREATE TRIGGER IF NOT EXISTS \(Self.quote("\(ftsTable)_ad")) AFTER DELETE ON \(qTable) BEGIN
                INSERT INTO \(qFTS)(\(qFTS), rowid, \(qColumn)) VALUES ('delete', old.rowid, old.\(qColumn));
            END;

            CREATE TRIGGER IF NOT EXISTS \(Self.quote("\(ftsTable)_au")) AFTER UPDATE ON \(qTable) BEGIN
                INSERT INTO \(qFTS)(\(qFTS), rowid, \(qColumn)) VALUES ('delete', old.rowid, old.\(qColumn));
                INSERT INTO \(qFTS)(rowid, \(qColumn)) VALUES (new.rowid, new.\(qColumn));
            END;

            INSERT INTO \(qFTS)(\(qFTS)) VALUES ('rebuild');
            """
        )
    }

    /// Runs a full-text query against `Record`'s FTS5 index and returns the matching records,
    /// ranked by relevance (bm25), best first.
    ///
    /// `query` is an FTS5 MATCH expression (e.g. `"vector OR embeddings"`, `"semantic search"`).
    func fullTextSearch<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        matching query: String,
        limit: Int? = nil
    ) async throws -> [Record] {
        await waitForTransactionAccess()
        return try fullTextRecords(type, matching: query, limit: limit)
    }
}

extension SQLiteKomaStore {
    func fullTextRecords<Record: KomaSQLiteFastPathRecord>(
        _ type: Record.Type,
        matching query: String,
        limit: Int? = nil
    ) throws -> [Record] {
        let qFTS = Self.quote("\(Record.komaTableName)_fts")
        let columns = Self.quotedSelectColumnList(Record.komaColumns, qualifier: "base")

        var sql = """
        SELECT \(columns)
        FROM \(Self.quote(Record.komaTableName)) AS base
        JOIN \(qFTS) ON \(qFTS).rowid = base.rowid
        WHERE \(qFTS) MATCH ?
        ORDER BY \(qFTS).rank
        """
        var arguments: [KomaSQLiteStorageValue] = [.text(query)]
        if let limit {
            sql += "\nLIMIT ?"
            arguments.append(.integer(Int64(limit)))
        }

        return try rawRecords(Record.self, sql, arguments: arguments)
    }
}
