#if canImport(CoreData)
import Benchmark
import CoreData
import Foundation
import KomaBenchmarkSupport

func registerCoreDataBenchmarks(small: [BenchmarkProject], large: [BenchmarkProject]) {
    Benchmark("coredata.sqlite.open.ensureSchema") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("coredata-open")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try CoreDataBenchmarkDatabase(path: path)
            blackHole(database)
        }
    }

    Benchmark("coredata.sqlite.batchInsert.1k") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("coredata-insert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try CoreDataBenchmarkDatabase(path: path)
            try database.insert(small)
            blackHole(database)
        }
    }

    Benchmark("coredata.sqlite.filteredOrderedFetch.10k.limit100") { benchmark in
        // Build + populate once (cached); measure only the fetch, not the 10k-row insert.
        let database = try await BenchmarkFixtureCache.shared.value("coredata-fetch") {
            let path = BenchmarkFixtures.databasePath("coredata-fetch")
            let database = try CoreDataBenchmarkDatabase(path: path)
            try database.insert(large)
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

/// @unchecked Sendable: benchmarks drive the container sequentially, letting a populated
/// instance be cached in BenchmarkFixtureCache and reused across measured iterations.
private final class CoreDataBenchmarkDatabase: @unchecked Sendable {
    private static let entityName = "CoreDataBenchmarkProject"

    private let container: NSPersistentContainer

    init(path: String) throws {
        container = NSPersistentContainer(
            name: "KomaBenchmarkCoreData",
            managedObjectModel: Self.makeModel()
        )

        let description = NSPersistentStoreDescription(url: URL(fileURLWithPath: path))
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        container.viewContext.undoManager = nil
        container.viewContext.mergePolicy = NSMergePolicy(
            merge: .mergeByPropertyObjectTrumpMergePolicyType
        )
    }

    func insert(_ projects: [BenchmarkProject]) throws {
        let context = container.newBackgroundContext()
        context.undoManager = nil
        context.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)

        try context.performAndWait {
            guard let entity = NSEntityDescription.entity(forEntityName: Self.entityName, in: context) else {
                throw CoreDataBenchmarkError.missingEntity(Self.entityName)
            }

            let objects = projects.map(Self.dictionary(for:))
            let request = NSBatchInsertRequest(entity: entity, objects: objects)
            try context.execute(request)
            if context.hasChanges {
                try context.save()
            }
        }
    }

    func fetchActiveProjects(limit: Int) throws -> [BenchmarkProject] {
        let context = container.newBackgroundContext()
        context.undoManager = nil

        return try context.performAndWait {
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "deletedAt == nil")
            request.sortDescriptors = [NSSortDescriptor(key: "name", ascending: true)]
            request.fetchLimit = limit
            request.returnsObjectsAsFaults = false

            return try context.fetch(request).map(Self.project(from:))
        }
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = Self.entityName
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            Self.attribute("id", type: .stringAttributeType),
            Self.attribute("name", type: .stringAttributeType),
            Self.attribute("slug", type: .stringAttributeType),
            Self.attribute("deletedAt", type: .doubleAttributeType, isOptional: true),
            Self.attribute("score", type: .integer64AttributeType),
            Self.attribute("updatedAt", type: .doubleAttributeType),
            Self.attribute("summary", type: .stringAttributeType)
        ]
        model.entities = [entity]
        return model
    }

    private static func attribute(
        _ name: String,
        type: NSAttributeType,
        isOptional: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        return attribute
    }

    private static func dictionary(for project: BenchmarkProject) -> [String: Any] {
        var dictionary: [String: Any] = [
            "id": project.id,
            "name": project.name,
            "slug": project.slug,
            "score": project.score,
            "updatedAt": project.updatedAt,
            "summary": project.summary
        ]
        if let deletedAt = project.deletedAt {
            dictionary["deletedAt"] = deletedAt
        }
        return dictionary
    }

    private static func project(from object: NSManagedObject) -> BenchmarkProject {
        BenchmarkProject(
            id: object.value(forKey: "id") as? String ?? "",
            name: object.value(forKey: "name") as? String ?? "",
            slug: object.value(forKey: "slug") as? String ?? "",
            deletedAt: object.value(forKey: "deletedAt") as? Double,
            score: object.value(forKey: "score") as? Int ?? 0,
            updatedAt: object.value(forKey: "updatedAt") as? Double ?? 0,
            summary: object.value(forKey: "summary") as? String ?? ""
        )
    }
}

private enum CoreDataBenchmarkError: Error {
    case missingEntity(String)
}
#endif
