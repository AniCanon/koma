import Foundation
import Koma
import KomaMacros

struct Project: Codable, Equatable {
    let id: String
    let name: String
    let slug: String
    let deletedAt: Date?
}

struct ProjectListParams: Codable, Equatable {
    var search: String?

    init(search: String? = nil) {
        self.search = search
    }
}

@KomaEntity(table: "projects", as: Project.self)
struct ProjectRecord: KomaRemoteRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String
    var deletedAt: Date?

    @KomaIgnore
    var displayName: String {
        name
    }

    init(id: String, name: String, slug: String, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.deletedAt = deletedAt
    }
}

struct FeatureRecord: KomaEntityRecord, Equatable {
    var id: String
    var isFavorite: Bool
    var payload: Data

    struct Columns {
        let id = KomaColumn<String>("id")
        let isFavorite = KomaColumn<Bool>("isFavorite")
        let payload = KomaColumn<Data>("payload")
    }

    static let columns = Columns()
    static let komaTableName = "features"
    static let komaPrimaryKey = "id"
    static let komaColumns: [KomaColumnMetadata] = [
        .init(name: "id", storage: .text, isPrimaryKey: true),
        .init(name: "isFavorite", storage: .integer),
        .init(name: "payload", storage: .blob)
    ]
}

@KomaEntity(table: "macro_features")
struct MacroFeatureRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var isFavorite: Bool
    var payload: Data
    var createdAt: Date?

    init(id: String, isFavorite: Bool, payload: Data, createdAt: Date? = nil) {
        self.id = id
        self.isFavorite = isFavorite
        self.payload = payload
        self.createdAt = createdAt
    }
}

@KomaEntity(table: "migration_auto_projects")
struct MigrationProjectV1Record: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@KomaEntity(table: "migration_auto_projects")
struct MigrationProjectV2Record: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String?

    init(id: String, name: String, slug: String? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
    }
}

@KomaEntity(table: "migration_rename_projects")
struct RenameProjectV1Record: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

@KomaEntity(table: "migration_rename_projects")
struct RenameProjectV2Record: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

enum RenameProjectMigrations: KomaMigrationPack {
    static let namespace = "projects.rename"

    static let migrations = [
        Migration(1, 2) {
            RenameColumn(RenameProjectV2Record.self, from: "title", to: \.name)
            AddIndex(RenameProjectV2Record.self, \.name)
        }
    ]
}

@KomaResource(basePath: "projects", record: ProjectRecord.self)
enum ProjectResources {
    @KomaRoute(
        .get(as: [Project].self),
        cache: .collection("projects", staleAfter: .minutes(5))
    )
    case list(ProjectListParams = .init())

    @KomaRoute(.get("{projectId}", as: Project.self), cache: .entity("projects"))
    case detail(projectId: String)
}

struct ProjectDateParams: Codable, Equatable {
    var updatedAfter: Date
}

struct ProjectCreateBody: Codable, Equatable {
    var name: String
    var createdAt: Date
}

@KomaResource(basePath: "projects", record: ProjectRecord.self)
enum ProjectEncodingResources {
    @KomaRoute(.get("updated", as: [Project].self))
    case updated(ProjectDateParams)

    @KomaRoute(.get("search", as: [Project].self))
    case search(search: String?, page: Int = 1)

    @KomaRoute(.post(as: Project.self))
    case create(body: ProjectCreateBody)
}
