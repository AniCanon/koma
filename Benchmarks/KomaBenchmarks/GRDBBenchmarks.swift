import Benchmark
import Foundation
import GRDB
import Koma
import KomaBenchmarkSupport

// Load the SQLite3 module GRDB's serialized (inlinable) SIL references, so `-O` can deserialize
// it in this target — which also links Koma's vendored CKomaSQLite. Without this the Swift 6.3
// release build aborts in `Row.decode<Double>` with "module 'SQLite3' was not loaded".
import SQLite3

func registerGRDBBenchmarks(small: [BenchmarkProject], large: [BenchmarkProject]) {
    Benchmark("grdb.sqlite.open.ensureSchema") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("grdb-open")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try GRDBBenchmarkDatabase(path: path)
            blackHole(database)
        }
    }

    Benchmark("grdb.sqlite.batchUpsert.1k") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("grdb-upsert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try GRDBBenchmarkDatabase(path: path)
            try database.upsert(small)
            blackHole(database)
        }
    }

    Benchmark("grdb.sqlite.filteredOrderedFetch.10k.limit100") { benchmark in
        // Build + populate once (cached); measure only the fetch, not the 10k-row insert.
        let database = try await BenchmarkFixtureCache.shared.value("grdb-fetch") {
            let path = BenchmarkFixtures.databasePath("grdb-fetch")
            let database = try GRDBBenchmarkDatabase(path: path)
            try database.upsert(large)
            return database
        }

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let projects = try database.fetchActiveProjects(limit: 100)
            blackHole(projects.count)
        }
        benchmark.stopMeasurement()
    }
}

/// @unchecked Sendable: benchmarks drive the queue sequentially, letting a populated instance
/// be cached in BenchmarkFixtureCache and reused across measured iterations.
private final class GRDBBenchmarkDatabase: @unchecked Sendable {
    private let queue: DatabaseQueue

    init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        // PRAGMA journal_mode cannot take effect inside a transaction, and `write` wraps its
        // closure in one — the pragma was silently leaving the database in rollback-journal
        // mode, skipping the WAL setup cost every other provider pays in this benchmark.
        try queue.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA journal_mode = WAL")
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try database.execute(
                sql: """
                CREATE TABLE IF NOT EXISTS benchmark_projects (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT,
                    slug TEXT,
                    deletedAt REAL,
                    score INTEGER,
                    updatedAt REAL,
                    summary TEXT
                )
                """
            )
        }
    }

    func upsert(_ projects: [BenchmarkProject]) throws {
        try queue.write { database in
            for project in projects {
                try database.execute(
                    sql: """
                    INSERT INTO benchmark_projects (id, name, slug, deletedAt, score, updatedAt, summary)
                    VALUES (:id, :name, :slug, :deletedAt, :score, :updatedAt, :summary)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        slug = excluded.slug,
                        deletedAt = excluded.deletedAt,
                        score = excluded.score,
                        updatedAt = excluded.updatedAt,
                        summary = excluded.summary
                    """,
                    arguments: [
                        "id": project.id,
                        "name": project.name,
                        "slug": project.slug,
                        "deletedAt": project.deletedAt,
                        "score": project.score,
                        "updatedAt": project.updatedAt,
                        "summary": project.summary
                    ]
                )
            }
        }
    }

    func fetchActiveProjects(limit: Int) throws -> [BenchmarkProject] {
        try queue.read { database in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT id, name, slug, deletedAt, score, updatedAt, summary
                FROM benchmark_projects
                WHERE deletedAt IS NULL
                ORDER BY name ASC
                LIMIT :limit
                """,
                arguments: ["limit": limit]
            )

            return rows.map { row in
                BenchmarkProject(
                    id: row["id"],
                    name: row["name"],
                    slug: row["slug"],
                    deletedAt: row["deletedAt"],
                    score: row["score"],
                    updatedAt: row["updatedAt"],
                    summary: row["summary"]
                )
            }
        }
    }
}

// MARK: - Memory store (FTS5 + vector + hybrid) — competition baseline for the new Koma APIs.

/// GRDB equivalents of `fullTextSearch` / `nearest` / `hybridSearch` over the same 10k / 384-dim
/// corpus as the `koma.sqlite.*` benchmarks, written the idiomatic GRDB way (lean rowid+embedding
/// scan, typed hydrate of the winners, RRF). Compare each `grdb.*` against its `koma.*` sibling.
func registerGRDBMemoryBenchmarks() {
    func database(_ label: String) async throws -> GRDBMemoryDatabase {
        try await BenchmarkFixtureCache.shared.value(label) {
            let database = try GRDBMemoryDatabase(path: BenchmarkFixtures.databasePath(label))
            try database.populate(count: MemoryBenchmarkFixtures.corpus)
            return database
        }
    }

    Benchmark("grdb.sqlite.fullTextSearch.10k") { benchmark in
        let database = try await database("grdb-memories-fts")
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try blackHole(database.fullTextSearch("swift", limit: 20).count)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("grdb.sqlite.nearest.10k.dim384") { benchmark in
        let database = try await database("grdb-memories-nearest")
        let query = MemoryBenchmarkFixtures.query
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try blackHole(database.nearest(to: query, limit: 20).count)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("grdb.sqlite.hybridSearch.10k.dim384") { benchmark in
        let database = try await database("grdb-memories-hybrid")
        let query = MemoryBenchmarkFixtures.query
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try blackHole(database.hybridSearch(matching: "swift", near: query, limit: 20).count)
        }
        benchmark.stopMeasurement()
    }
}

private struct GRDBMemory: Decodable, FetchableRecord {
    var id: String
    var content: String
    var embedding: Data
}

/// @unchecked Sendable: the queue is driven sequentially, so a populated instance can be cached in
/// BenchmarkFixtureCache and reused across measured iterations.
private final class GRDBMemoryDatabase: @unchecked Sendable {
    private let queue: DatabaseQueue

    init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        // See GRDBBenchmarkDatabase: the WAL pragma is a no-op inside `write`'s transaction.
        try queue.writeWithoutTransaction { database in
            try database.execute(sql: "PRAGMA journal_mode = WAL")
            try database.execute(
                sql: """
                CREATE TABLE IF NOT EXISTS memories (
                    id TEXT PRIMARY KEY NOT NULL,
                    content TEXT NOT NULL,
                    embedding BLOB NOT NULL
                )
                """
            )
            try database.execute(
                sql: "CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts "
                    + "USING fts5(content, content='memories', content_rowid='rowid')"
            )
            try database.execute(
                sql: """
                CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
                    INSERT INTO memories_fts(rowid, content) VALUES (new.rowid, new.content);
                END
                """
            )
        }
    }

    func populate(count: Int) throws {
        try queue.write { database in
            for index in 0 ..< count {
                try database.execute(
                    sql: "INSERT INTO memories (id, content, embedding) VALUES (?, ?, ?)",
                    arguments: [
                        "\(index)",
                        MemoryBenchmarkFixtures.content(index),
                        MemoryBenchmarkFixtures.blobs[index]
                    ]
                )
            }
        }
    }

    func fullTextSearch(_ query: String, limit: Int) throws -> [GRDBMemory] {
        try queue.read { database in
            try GRDBMemory.fetchAll(
                database,
                sql: """
                SELECT m.id, m.content, m.embedding
                FROM memories AS m
                JOIN memories_fts ON memories_fts.rowid = m.rowid
                WHERE memories_fts MATCH ?
                ORDER BY memories_fts.rank
                LIMIT ?
                """,
                arguments: [query, limit]
            )
        }
    }

    func nearest(to query: [Double], limit: Int) throws -> [(memory: GRDBMemory, similarity: Double)] {
        try queue.read { database in
            // Lean scan: rowid + embedding only, cosine in Swift, then hydrate just the winners.
            let cursor = try Row.fetchCursor(database, sql: "SELECT rowid, embedding FROM memories")
            var scored: [(rowid: Int64, similarity: Double)] = []
            while let row = try cursor.next() {
                let embedding: Data = row["embedding"]
                scored.append((row["rowid"], KomaVector.cosine(query, KomaVector.decode(embedding))))
            }

            let winners = Array(scored.sorted { $0.similarity > $1.similarity }.prefix(limit))
            guard !winners.isEmpty else { return [] }

            let ids = winners.map { String($0.rowid) }.joined(separator: ", ")
            let ranking = winners.enumerated()
                .map { "WHEN \($0.element.rowid) THEN \($0.offset)" }
                .joined(separator: " ")
            let memories = try GRDBMemory.fetchAll(
                database,
                sql: """
                SELECT id, content, embedding FROM memories
                WHERE rowid IN (\(ids))
                ORDER BY CASE rowid \(ranking) END
                """
            )
            return zip(memories, winners).map { (memory: $0, similarity: $1.similarity) }
        }
    }

    func hybridSearch(matching query: String, near vector: [Double], limit: Int, candidateLimit: Int = 50) throws -> [GRDBMemory] {
        let keyword = try fullTextSearch(query, limit: candidateLimit)
        let semantic = try nearest(to: vector, limit: candidateLimit).map(\.memory)
        let fused = KomaVector.fuse([keyword, semantic], by: \.id)
        return Array(fused.prefix(limit))
    }
}
