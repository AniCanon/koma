import CKomaSQLite
import Foundation
import KomaBenchmarkSupport

public final class RawSQLiteBenchmarkDatabase {
    private var connection: OpaquePointer?

    public init(path: String) throws {
        guard sqlite3_open_v2(path, &connection, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK
        else {
            throw RawSQLiteBenchmarkError.openFailed(errorMessage)
        }

        try execute("PRAGMA journal_mode = WAL")
        try execute("PRAGMA foreign_keys = ON")
        try execute(
            """
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
        try execute(
            """
            CREATE TABLE IF NOT EXISTS benchmark_characters (
                id TEXT PRIMARY KEY NOT NULL,
                projectId TEXT,
                name TEXT,
                role TEXT
            )
            """
        )
    }

    deinit {
        if let connection {
            sqlite3_close(connection)
        }
    }

    public func upsert(_ projects: [BenchmarkProject]) throws {
        let sql = """
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

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            for project in projects {
                sqlite3_bind_text(statement, 1, project.id, -1, rawSQLiteTransient)
                sqlite3_bind_text(statement, 2, project.name, -1, rawSQLiteTransient)
                sqlite3_bind_text(statement, 3, project.slug, -1, rawSQLiteTransient)
                if let deletedAt = project.deletedAt {
                    sqlite3_bind_double(statement, 4, deletedAt)
                } else {
                    sqlite3_bind_null(statement, 4)
                }
                sqlite3_bind_int64(statement, 5, Int64(project.score))
                sqlite3_bind_double(statement, 6, project.updatedAt)
                sqlite3_bind_text(statement, 7, project.summary, -1, rawSQLiteTransient)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw RawSQLiteBenchmarkError.executionFailed(errorMessage)
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

    public func upsertCharacters(_ characters: [BenchmarkCharacter]) throws {
        let sql = """
        INSERT INTO benchmark_characters (id, projectId, name, role)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            projectId = excluded.projectId,
            name = excluded.name,
            role = excluded.role
        """

        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let statement = try prepare(sql)
            defer { sqlite3_finalize(statement) }

            for character in characters {
                sqlite3_bind_text(statement, 1, character.id, -1, rawSQLiteTransient)
                sqlite3_bind_text(statement, 2, character.projectId, -1, rawSQLiteTransient)
                sqlite3_bind_text(statement, 3, character.name, -1, rawSQLiteTransient)
                sqlite3_bind_text(statement, 4, character.role, -1, rawSQLiteTransient)

                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw RawSQLiteBenchmarkError.executionFailed(errorMessage)
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

    public func fetchActiveProjects(limit: Int) throws -> [BenchmarkProject] {
        let statement = try prepare(
            """
            SELECT id, name, slug, deletedAt, score, updatedAt, summary
            FROM benchmark_projects
            WHERE deletedAt IS NULL
            ORDER BY name ASC
            LIMIT ?
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(limit))

        var projects: [BenchmarkProject] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                break
            }
            guard step == SQLITE_ROW else {
                throw RawSQLiteBenchmarkError.executionFailed(errorMessage)
            }
            projects.append(
                BenchmarkProject(
                    id: Self.text(statement, 0),
                    name: Self.text(statement, 1),
                    slug: Self.text(statement, 2),
                    deletedAt: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3),
                    score: Int(sqlite3_column_int64(statement, 4)),
                    updatedAt: sqlite3_column_double(statement, 5),
                    summary: Self.text(statement, 6)
                )
            )
        }
        return projects
    }

    public func fetchProjectsWithLeadCharacters(limit: Int) throws -> [BenchmarkProject] {
        try fetchProjects(
            sql: """
            SELECT DISTINCT p.id, p.name, p.slug, p.deletedAt, p.score, p.updatedAt, p.summary
            FROM benchmark_projects p
            INNER JOIN benchmark_characters c ON p.id = c.projectId
            WHERE p.deletedAt IS NULL AND c.role = 'lead'
            ORDER BY p.name ASC
            LIMIT ?
            """,
            limit: limit
        )
    }

    public func fetchProjectsWithoutCharacters(limit: Int) throws -> [BenchmarkProject] {
        try fetchProjects(
            sql: """
            SELECT DISTINCT p.id, p.name, p.slug, p.deletedAt, p.score, p.updatedAt, p.summary
            FROM benchmark_projects p
            LEFT JOIN benchmark_characters c ON p.id = c.projectId
            WHERE p.deletedAt IS NULL AND c.id IS NULL
            ORDER BY p.name ASC
            LIMIT ?
            """,
            limit: limit
        )
    }

    public func fetchProjectsRightJoinedToLeadCharacters(limit: Int) throws -> [BenchmarkProject] {
        try fetchProjects(
            sql: """
            SELECT DISTINCT p.id, p.name, p.slug, p.deletedAt, p.score, p.updatedAt, p.summary
            FROM benchmark_projects p
            RIGHT JOIN benchmark_characters c ON p.id = c.projectId
            WHERE p.id IS NOT NULL AND p.deletedAt IS NULL AND c.role = 'lead'
            ORDER BY p.name ASC
            LIMIT ?
            """,
            limit: limit
        )
    }

    private func fetchProjects(sql: String, limit: Int) throws -> [BenchmarkProject] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_int64(statement, 1, Int64(limit))

        var projects: [BenchmarkProject] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE {
                break
            }
            guard step == SQLITE_ROW else {
                throw RawSQLiteBenchmarkError.executionFailed(errorMessage)
            }
            projects.append(Self.project(from: statement))
        }
        return projects
    }

    private var errorMessage: String {
        guard let connection,
              let message = sqlite3_errmsg(connection)
        else {
            return "Unknown SQLite error."
        }
        return String(cString: message)
    }

    private func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(connection, sql, nil, nil, &error) != SQLITE_OK {
            let message = error.map { String(cString: $0) } ?? errorMessage
            sqlite3_free(error)
            throw RawSQLiteBenchmarkError.executionFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else {
            throw RawSQLiteBenchmarkError.executionFailed(errorMessage)
        }
        return statement
    }

    private static func text(_ statement: OpaquePointer, _ index: Int32) -> String {
        sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""
    }

    private static func project(from statement: OpaquePointer) -> BenchmarkProject {
        BenchmarkProject(
            id: text(statement, 0),
            name: text(statement, 1),
            slug: text(statement, 2),
            deletedAt: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3),
            score: Int(sqlite3_column_int64(statement, 4)),
            updatedAt: sqlite3_column_double(statement, 5),
            summary: text(statement, 6)
        )
    }
}

private enum RawSQLiteBenchmarkError: Error {
    case openFailed(String)
    case executionFailed(String)
}

private let rawSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
