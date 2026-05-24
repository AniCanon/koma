#if canImport(SwiftData)
import Benchmark
import Foundation
import KomaBenchmarkSupport
import SwiftData

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
func registerSwiftDataBenchmarks(small: [BenchmarkProject], large: [BenchmarkProject]) {
    Benchmark("swiftdata.sqlite.open.ensureSchema") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("swiftdata-open")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try SwiftDataBenchmarkDatabase(path: path)
            blackHole(database)
        }
    }

    Benchmark("swiftdata.sqlite.insert.1k") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("swiftdata-insert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try SwiftDataBenchmarkDatabase(path: path)
            try database.insert(small)
            blackHole(database)
        }
    }

    Benchmark("swiftdata.sqlite.filteredOrderedFetch.10k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("swiftdata-fetch")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let database = try SwiftDataBenchmarkDatabase(path: path)
        try database.insert(large)

        for _ in benchmark.scaledIterations {
            let projects = try database.fetchActiveProjects(limit: 100)
            blackHole(projects.count)
        }
    }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
@Model
private final class SwiftDataBenchmarkProject {
    @Attribute(.unique) var id: String
    var name: String
    var slug: String
    var deletedAt: Double?
    var score: Int
    var updatedAt: Double
    var summary: String

    init(project: BenchmarkProject) {
        id = project.id
        name = project.name
        slug = project.slug
        deletedAt = project.deletedAt
        score = project.score
        updatedAt = project.updatedAt
        summary = project.summary
    }

    var benchmarkProject: BenchmarkProject {
        BenchmarkProject(
            id: id,
            name: name,
            slug: slug,
            deletedAt: deletedAt,
            score: score,
            updatedAt: updatedAt,
            summary: summary
        )
    }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
private final class SwiftDataBenchmarkDatabase {
    private let container: ModelContainer
    private let context: ModelContext

    init(path: String) throws {
        let schema = Schema([SwiftDataBenchmarkProject.self])
        let configuration = ModelConfiguration(
            "KomaBenchmarkSwiftData",
            schema: schema,
            url: URL(fileURLWithPath: path),
            allowsSave: true
        )
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func insert(_ projects: [BenchmarkProject]) throws {
        for project in projects {
            context.insert(SwiftDataBenchmarkProject(project: project))
        }
        try context.save()
    }

    func fetchActiveProjects(limit: Int) throws -> [BenchmarkProject] {
        var descriptor = FetchDescriptor<SwiftDataBenchmarkProject>(
            predicate: #Predicate { project in
                project.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        descriptor.fetchLimit = limit

        return try context.fetch(descriptor).map(\.benchmarkProject)
    }
}
#endif
