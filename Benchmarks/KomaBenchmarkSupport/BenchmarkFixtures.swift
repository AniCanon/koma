import Foundation

public enum BenchmarkFixtures {
    public static func projects(_ count: Int) -> [BenchmarkProject] {
        (0 ..< count).map { index in
            BenchmarkProject(
                id: "project-\(index)",
                name: "Project \(String(format: "%05d", index))",
                slug: "project-\(index)",
                deletedAt: index.isMultiple(of: 10) ? Double(index) : nil,
                score: index % 100,
                updatedAt: Double(1_700_000_000 + index),
                summary: "Benchmark project \(index) with a stable AniCanon-shaped text field."
            )
        }
    }

    public static func responseBody(projects: [BenchmarkProject]) -> Data {
        try! JSONEncoder().encode(projects)
    }

    public static func characters(for projects: [BenchmarkProject]) -> [BenchmarkCharacter] {
        projects.enumerated().flatMap { index, project -> [BenchmarkCharacter] in
            guard !index.isMultiple(of: 7) else {
                return []
            }
            return [
                BenchmarkCharacter(
                    id: "\(project.id)-lead",
                    projectId: project.id,
                    name: "Lead \(project.name)",
                    role: "lead"
                ),
                BenchmarkCharacter(
                    id: "\(project.id)-support",
                    projectId: project.id,
                    name: "Support \(project.name)",
                    role: "support"
                )
            ]
        }
    }

    public static func graphQLResponseBody(projects: [BenchmarkProject]) -> Data {
        let projectObjects = projects.map { project -> [String: Any] in
            [
                "__typename": "Project",
                "id": project.id,
                "name": project.name,
                "slug": project.slug,
                "deletedAt": project.deletedAt as Any,
                "score": project.score,
                "updatedAt": project.updatedAt,
                "summary": project.summary
            ]
        }
        let response: [String: Any] = [
            "data": [
                "projects": projectObjects
            ]
        ]
        return try! JSONSerialization.data(withJSONObject: response)
    }

    public static func databasePath(_ label: String) -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return directory
            .appendingPathComponent("koma-\(label)-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
            .path
    }

    public static func removeDatabaseFiles(_ path: String) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(atPath: path)
        try? fileManager.removeItem(atPath: "\(path)-shm")
        try? fileManager.removeItem(atPath: "\(path)-wal")
    }
}
