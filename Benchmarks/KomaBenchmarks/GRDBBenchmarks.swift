import Benchmark
import Foundation
import GRDB

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
        let path = BenchmarkFixtures.databasePath("grdb-fetch")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let database = try GRDBBenchmarkDatabase(path: path)
        try database.upsert(large)

        for _ in benchmark.scaledIterations {
            let projects = try database.fetchActiveProjects(limit: 100)
            blackHole(projects.count)
        }
    }
}

private final class GRDBBenchmarkDatabase {
    private let queue: DatabaseQueue

    init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        try queue.write { database in
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
