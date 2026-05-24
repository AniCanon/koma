import Foundation
import KomaAndroidBenchmarkCore
import KomaBenchmarkSupport
import SQLite

func makeSQLiteSwiftBenchmarks() -> [AndroidBenchmark] {
    let small = BenchmarkFixtures.projects(1000)
    let large = BenchmarkFixtures.projects(10000)
    let largeCharacters = BenchmarkFixtures.characters(for: large)
    let fetchDatabase = AndroidLazy {
        let database = try SQLiteSwiftBenchmarkDatabase(path: BenchmarkFixtures.databasePath("android-sqliteswift-fetch"))
        try database.upsert(large)
        return database
    }
    let innerJoinDatabase = AndroidLazy {
        let database = try SQLiteSwiftBenchmarkDatabase(path: BenchmarkFixtures.databasePath("android-sqliteswift-inner-join"))
        try database.upsert(large)
        try database.upsertCharacters(largeCharacters)
        return database
    }
    let leftJoinDatabase = AndroidLazy {
        let database = try SQLiteSwiftBenchmarkDatabase(path: BenchmarkFixtures.databasePath("android-sqliteswift-left-join"))
        try database.upsert(large)
        try database.upsertCharacters(largeCharacters)
        return database
    }

    return [
        AndroidBenchmark(name: "android.sqliteswift.sqlite.open.ensureSchema", iterations: 80) {
            let path = BenchmarkFixtures.databasePath("android-sqliteswift-open")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            _ = try SQLiteSwiftBenchmarkDatabase(path: path)
        },
        AndroidBenchmark(name: "android.sqliteswift.sqlite.batchUpsert.1k", iterations: 20) {
            let path = BenchmarkFixtures.databasePath("android-sqliteswift-upsert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try SQLiteSwiftBenchmarkDatabase(path: path)
            try database.upsert(small)
        },
        AndroidBenchmark(name: "android.sqliteswift.sqlite.filteredOrderedFetch.10k.limit100", iterations: 20) {
            let projects = try fetchDatabase.get().fetchActiveProjects(limit: 100)
            AndroidBlackHole.consume(projects.count)
        },
        AndroidBenchmark(name: "android.sqliteswift.sqlite.innerJoinFilter.10k.limit100", iterations: 20) {
            let projects = try innerJoinDatabase.get().fetchProjectsWithLeadCharacters(limit: 100)
            AndroidBlackHole.consume(projects.count)
        },
        AndroidBenchmark(name: "android.sqliteswift.sqlite.leftJoinMissing.10k.limit100", iterations: 20) {
            let projects = try leftJoinDatabase.get().fetchProjectsWithoutCharacters(limit: 100)
            AndroidBlackHole.consume(projects.count)
        }
    ]
}

private final class SQLiteSwiftBenchmarkDatabase {
    private let connection: Connection

    init(path: String) throws {
        connection = try Connection(path)
        try connection.execute("PRAGMA journal_mode = WAL")
        try connection.execute("PRAGMA foreign_keys = ON")
        try connection.execute(Self.projectSchema)
        try connection.execute(Self.characterSchema)
    }

    func upsert(_ projects: [BenchmarkProject]) throws {
        let statement = try connection.prepare(Self.projectUpsertSQL)
        try connection.transaction(.immediate) {
            for project in projects {
                try statement.run(Self.bindings(for: project))
            }
        }
    }

    func upsertCharacters(_ characters: [BenchmarkCharacter]) throws {
        let statement = try connection.prepare(Self.characterUpsertSQL)
        try connection.transaction(.immediate) {
            for character in characters {
                try statement.run(Self.bindings(for: character))
            }
        }
    }

    func fetchActiveProjects(limit: Int) throws -> [BenchmarkProject] {
        try fetchProjects(sql: Self.activeProjectsSQL, limit: limit)
    }

    func fetchProjectsWithLeadCharacters(limit: Int) throws -> [BenchmarkProject] {
        try fetchProjects(sql: Self.leadCharactersSQL, limit: limit)
    }

    func fetchProjectsWithoutCharacters(limit: Int) throws -> [BenchmarkProject] {
        try fetchProjects(sql: Self.missingCharactersSQL, limit: limit)
    }

    private func fetchProjects(sql: String, limit: Int) throws -> [BenchmarkProject] {
        let statement = try connection.prepare(sql, limit)
        return statement.map(Self.project(from:))
    }

    private static func bindings(for project: BenchmarkProject) -> [Binding?] {
        let deletedAt: Binding? = project.deletedAt.map(\.self)
        return [
            project.id,
            project.name,
            project.slug,
            deletedAt,
            project.score,
            project.updatedAt,
            project.summary
        ]
    }

    private static func bindings(for character: BenchmarkCharacter) -> [Binding?] {
        [
            character.id,
            character.projectId,
            character.name,
            character.role
        ]
    }

    private static func project(from row: [Binding?]) -> BenchmarkProject {
        BenchmarkProject(
            id: row[0] as? String ?? "",
            name: row[1] as? String ?? "",
            slug: row[2] as? String ?? "",
            deletedAt: row[3].flatMap(double),
            score: row[4].flatMap(int) ?? 0,
            updatedAt: row[5].flatMap(double) ?? 0,
            summary: row[6] as? String ?? ""
        )
    }

    private static func double(_ value: Binding) -> Double? {
        if let value = value as? Double {
            return value
        }
        if let value = value as? Int64 {
            return Double(value)
        }
        if let value = value as? Int {
            return Double(value)
        }
        return nil
    }

    private static func int(_ value: Binding) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? Int64 {
            return Int(value)
        }
        return nil
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
    VALUES (?, ?, ?, ?, ?, ?, ?)
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
    VALUES (?, ?, ?, ?)
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
    LIMIT ?
    """

    private static let leadCharactersSQL = """
    SELECT DISTINCT p.id, p.name, p.slug, p.deletedAt, p.score, p.updatedAt, p.summary
    FROM benchmark_projects p
    INNER JOIN benchmark_characters c ON p.id = c.projectId
    WHERE p.deletedAt IS NULL AND c.role = 'lead'
    ORDER BY p.name ASC
    LIMIT ?
    """

    private static let missingCharactersSQL = """
    SELECT DISTINCT p.id, p.name, p.slug, p.deletedAt, p.score, p.updatedAt, p.summary
    FROM benchmark_projects p
    LEFT JOIN benchmark_characters c ON p.id = c.projectId
    WHERE p.deletedAt IS NULL AND c.id IS NULL
    ORDER BY p.name ASC
    LIMIT ?
    """
}
