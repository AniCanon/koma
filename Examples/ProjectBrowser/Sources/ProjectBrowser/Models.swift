import Foundation
import Koma
import KomaMacros

@KomaModel(record: CharacterRecord.self)
struct CharacterModel {
    var id: String
    var projectId: String
    var name: String
    var deletedAt: Date?
}

@KomaModel(record: ProjectRecord.self)
struct ProjectModel {
    var id: String
    var name: String
    var slug: String
    var deletedAt: Date?

    enum Relations {
        @KomaHasMany(
            CharacterRecord.self,
            local: \ProjectRecord.Columns.id,
            foreign: \CharacterRecord.Columns.projectId,
            model: CharacterModel.self
        )
        case characters
    }
}
