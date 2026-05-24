# Migrations

Koma automatically adds missing columns for simple additive changes. Structural changes use modular migration packs.

```swift
enum ProjectMigrations: KomaMigrationPack {
    static let namespace = "projects"

    static let migrations = [
        Migration(1, 2) {
            RenameColumn(ProjectRecord.self, from: "title", to: \.name)
            AddColumn(ProjectRecord.self, \.slug, storage: .text, default: .string(""))
            AddIndex(ProjectRecord.self, \.slug, unique: true)
        }
    ]
}
```

Use schema modules to avoid one large schema file.

```swift
enum ProjectSchema: KomaSchemaModule {
    static let entities: [any KomaEntityRecord.Type] = [
        ProjectRecord.self,
        CharacterRecord.self
    ]

    static var migrationPacks: [any KomaMigrationPack.Type] {
        [ProjectMigrations.self]
    }
}

let schema = KomaSchema(modules: [ProjectSchema.self])
```

Available steps include adding, dropping, and renaming columns; renaming tables; creating tables; adding indexes; and executing scoped SQL.
