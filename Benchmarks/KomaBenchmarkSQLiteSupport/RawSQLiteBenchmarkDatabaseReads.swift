import CKomaSQLite
import KomaBenchmarkSupport

private let rawSQLiteReadTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public extension RawSQLiteBenchmarkDatabase {
    func fetchActiveProjects(limit: Int) throws -> [BenchmarkProject] {
        try fetchProjects(
            sql: """
            SELECT id, name, slug, deletedAt, score, updatedAt, summary
            FROM benchmark_projects
            WHERE deletedAt IS NULL
            ORDER BY name ASC
            LIMIT ?
            """,
            limit: limit
        )
    }

    func fetchProjectsWithLeadCharacters(limit: Int) throws -> [BenchmarkProject] {
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

    func fetchProjectsWithoutCharacters(limit: Int) throws -> [BenchmarkProject] {
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

    func fetchProjectsRightJoinedToLeadCharacters(limit: Int) throws -> [BenchmarkProject] {
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

    func fetchProject(id: String) throws -> BenchmarkProject? {
        let statement = try prepare(
            """
            SELECT id, name, slug, deletedAt, score, updatedAt, summary
            FROM benchmark_projects
            WHERE id = ?
            LIMIT 1
            """
        )
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id, -1, rawSQLiteReadTransient)

        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            return Self.project(from: statement)
        case SQLITE_DONE:
            return nil
        default:
            throw RawSQLiteBenchmarkError.executionFailed(errorMessage)
        }
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
