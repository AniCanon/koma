import Koma

enum ProjectSchema: KomaSchemaModule {
    static var entities: [any KomaEntityRecord.Type] {
        [
            ProjectRecord.self,
            CharacterRecord.self
        ]
    }

    static var migrationPacks: [any KomaMigrationPack.Type] {
        [
            ProjectMigrations.self
        ]
    }
}

enum ProjectMigrations: KomaMigrationPack {
    static let namespace = "projects"

    static var migrations: [KomaMigration] {
        [
            Migration(1, 2) {
                AddIndex(
                    CharacterRecord.self,
                    \.projectId,
                    name: "idx_characters_project_id"
                )
            }
        ]
    }
}
