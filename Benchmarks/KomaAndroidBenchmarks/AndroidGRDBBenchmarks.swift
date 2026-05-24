import Foundation
import GRDB
import KomaAndroidBenchmarkCore
import KomaBenchmarkSupport

func makeAndroidGRDBBenchmarks() -> [AndroidBenchmark] {
    let small = BenchmarkFixtures.projects(1000)
    let large = BenchmarkFixtures.projects(10000)
    let largeCharacters = BenchmarkFixtures.characters(for: large)
    let fetchDatabase = AndroidLazy {
        let database = try AndroidGRDBBenchmarkDatabase(path: BenchmarkFixtures.databasePath("android-grdb-fetch"))
        try database.upsert(large)
        return database
    }
    let innerJoinDatabase = AndroidLazy {
        let database = try AndroidGRDBBenchmarkDatabase(path: BenchmarkFixtures.databasePath("android-grdb-inner-join"))
        try database.upsert(large)
        try database.upsertCharacters(largeCharacters)
        return database
    }
    let leftJoinDatabase = AndroidLazy {
        let database = try AndroidGRDBBenchmarkDatabase(path: BenchmarkFixtures.databasePath("android-grdb-left-join"))
        try database.upsert(large)
        try database.upsertCharacters(largeCharacters)
        return database
    }

    return [
        AndroidBenchmark(name: "android.grdb.sqlite.open.ensureSchema", iterations: 80) {
            let path = BenchmarkFixtures.databasePath("android-grdb-open")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            _ = try AndroidGRDBBenchmarkDatabase(path: path)
        },
        AndroidBenchmark(name: "android.grdb.sqlite.batchUpsert.1k", iterations: 20) {
            let path = BenchmarkFixtures.databasePath("android-grdb-upsert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try AndroidGRDBBenchmarkDatabase(path: path)
            try database.upsert(small)
        },
        AndroidBenchmark(name: "android.grdb.sqlite.filteredOrderedFetch.10k.limit100", iterations: 20) {
            let projects = try fetchDatabase.get().fetchActiveProjects(limit: 100)
            AndroidBlackHole.consume(projects.count)
        },
        AndroidBenchmark(name: "android.grdb.sqlite.innerJoinFilter.10k.limit100", iterations: 20) {
            let projects = try innerJoinDatabase.get().fetchProjectsWithLeadCharacters(limit: 100)
            AndroidBlackHole.consume(projects.count)
        },
        AndroidBenchmark(name: "android.grdb.sqlite.leftJoinMissing.10k.limit100", iterations: 20) {
            let projects = try leftJoinDatabase.get().fetchProjectsWithoutCharacters(limit: 100)
            AndroidBlackHole.consume(projects.count)
        }
    ]
}

private final class AndroidGRDBBenchmarkDatabase {
    private let queue: DatabaseQueue

    init(path: String) throws {
        queue = try DatabaseQueue(path: path)
        try queue.write { database in
            try database.execute(sql: "PRAGMA journal_mode = WAL")
            try database.execute(sql: "PRAGMA foreign_keys = ON")
            try database.execute(sql: Self.projectSchema)
            try database.execute(sql: Self.characterSchema)
        }
    }

    func upsert(_ projects: [BenchmarkProject]) throws {
        try queue.write { database in
            for project in projects {
                try database.execute(
                    sql: Self.projectUpsertSQL,
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

    func upsertCharacters(_ characters: [BenchmarkCharacter]) throws {
        try queue.write { database in
            for character in characters {
                try database.execute(
                    sql: Self.characterUpsertSQL,
                    arguments: [
                        "id": character.id,
                        "projectId": character.projectId,
                        "name": character.name,
                        "role": character.role
                    ]
                )
            }
        }
    }

    func fetchActiveProjects(limit: Int) throws -> [BenchmarkProject] {
        try fetchProjects(sql: Self.activeProjectsSQL, arguments: ["limit": limit])
    }

    func fetchProjectsWithLeadCharacters(limit: Int) throws -> [BenchmarkProject] {
        try fetchProjects(sql: Self.leadCharactersSQL, arguments: ["limit": limit])
    }

    func fetchProjectsWithoutCharacters(limit: Int) throws -> [BenchmarkProject] {
        try fetchProjects(sql: Self.missingCharactersSQL, arguments: ["limit": limit])
    }

    private func fetchProjects(sql: String, arguments: StatementArguments) throws -> [BenchmarkProject] {
        try queue.read { database in
            try Row.fetchAll(database, sql: sql, arguments: arguments)
                .map { row in
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

    private static let projectSchema = """
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

    private static let characterSchema = """
    CREATE TABLE IF NOT EXISTS benchmark_characters (
        id TEXT PRIMARY KEY NOT NULL,
        projectId TEXT,
        name TEXT,
        role TEXT
    )
    """

    private static let projectUpsertSQL = """
    INSERT INTO benchmark_projects (id, name, slug, deletedAt, score, updatedAt, summary)
    VALUES (:id, :name, :slug, :deletedAt, :score, :updatedAt, :summary)
    ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        slug = excluded.slug,
        deletedAt = excluded.deletedAt,
        score = excluded.score,
        updatedAt = excluded.updatedAt,
        summary = excluded.summary
    """

    private static let characterUpsertSQL = """
    INSERT INTO benchmark_characters (id, projectId, name, role)
    VALUES (:id, :projectId, :name, :role)
    ON CONFLICT(id) DO UPDATE SET
        projectId = excluded.projectId,
        name = excluded.name,
        role = excluded.role
    """

    private static let activeProjectsSQL = """
    SELECT id, name, slug, deletedAt, score, updatedAt, summary
    FROM benchmark_projects
    WHERE deletedAt IS NULL
    ORDER BY name ASC
    LIMIT :limit
    """

    private static let leadCharactersSQL = """
    SELECT DISTINCT p.id, p.name, p.slug, p.deletedAt, p.score, p.updatedAt, p.summary
    FROM benchmark_projects p
    INNER JOIN benchmark_characters c ON p.id = c.projectId
    WHERE p.deletedAt IS NULL AND c.role = 'lead'
    ORDER BY p.name ASC
    LIMIT :limit
    """

    private static let missingCharactersSQL = """
    SELECT DISTINCT p.id, p.name, p.slug, p.deletedAt, p.score, p.updatedAt, p.summary
    FROM benchmark_projects p
    LEFT JOIN benchmark_characters c ON p.id = c.projectId
    WHERE p.deletedAt IS NULL AND c.id IS NULL
    ORDER BY p.name ASC
    LIMIT :limit
    """
}
