import Foundation
import Koma
import KomaMacros

@KomaEntity(table: "projects", as: Project.self)
struct ProjectRecord: KomaRemoteRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String
    var deletedAt: Date?

    @KomaIgnore
    var displayTitle: String {
        name
    }

    init(id: String, name: String, slug: String, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.deletedAt = deletedAt
    }
}

@KomaEntity(table: "characters", as: Character.self)
struct CharacterRecord: KomaRemoteRecord, Equatable {
    @KomaPrimaryKey var id: String
    var projectId: String
    var name: String
    var deletedAt: Date?

    init(id: String, projectId: String, name: String, deletedAt: Date? = nil) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.deletedAt = deletedAt
    }
}
