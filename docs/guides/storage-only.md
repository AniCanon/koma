# Storage-Only Mode

Koma can be used as a typed SQLite ORM without the network layer.

Use this mode when an app already has its own networking, does not need REST-backed refresh, or only wants a local database with typed queries, writes, migrations, and optional hydrated models.

## Dependencies

Storage-only apps depend on:

```swift
.product(name: "Koma", package: "koma"),
.product(name: "KomaMacros", package: "koma"),
.product(name: "KomaSQLite", package: "koma")
```

They do not need:

```swift
.product(name: "KomaHTTP", package: "koma")
```

They also do not need `KomaClient`, resource enums, transports, auth plugins, retry plugins, or scheduled refresh.

## Define Records

```swift
import Koma
import KomaMacros

@KomaEntity(table: "projects")
struct ProjectRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String
    var deletedAt: Date?
}
```

Records are passive value types. They describe table shape and queryable columns; they do not save themselves.

## Open a Store

```swift
import KomaSQLite

let store = try await SQLiteKomaStore.open(
    database: .applicationSupport("AniCanon.sqlite", appDirectory: "AniCanon")
)
```

With migrations:

```swift
let schema = KomaSchema(
    entities: [ProjectRecord.self],
    migrationPacks: [ProjectMigrations.self]
)

let store = try await SQLiteKomaStore.open(
    database: .applicationSupport("AniCanon.sqlite", appDirectory: "AniCanon"),
    schema: schema
)
```

## Write Data

```swift
try await store.upsert([
    ProjectRecord(id: "1", name: "Akira Boards", slug: "akira-boards", deletedAt: nil),
    ProjectRecord(id: "2", name: "Sakuga Notes", slug: "sakuga-notes", deletedAt: nil)
])
```

Use transactions when multiple writes should commit together:

```swift
try await store.transaction { tx in
    try await tx.upsert(projects)
    try await tx.delete(ProjectRecord.self)
        .where { $0.deletedAt != nil }
        .execute()
}
```

## Query Data

```swift
let projects = try await store.query(ProjectRecord.self)
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .limit(50)
    .fetch()
```

Convenience reads are available too:

```swift
let first = try await store.query(ProjectRecord.self)
    .where { $0.slug == "akira-boards" }
    .first()

let count = try await store.query(ProjectRecord.self)
    .where { $0.deletedAt == nil }
    .count()
```

## Add Models and Relationships

Storage-only mode can still use hydrated models and relationships.

```swift
@KomaModel(record: ProjectRecord.self, relations: ProjectRelations.self)
struct ProjectModel {
    var id: String
    var name: String
    var slug: String
    var deletedAt: Date?
}

let projects = try await store.query(ProjectModel.self)
    .where { $0.deletedAt == nil }
    .include(\.characters)
    .fetch()
```

Use this when app code wants relationship-aware models but does not need Koma to perform network refresh.

Storage-only mode also supports joins:

```swift
let projects = try await store.query(ProjectRecord.self)
    .join(CharacterRecord.self) { $0.id == $1.projectId }
    .where(CharacterRecord.self) { $0.name.hasPrefix("A") }
    .fetch()
```

## Add Network Later

The network layer is additive. A storage-only app can later add `KomaHTTP`, create a `KomaClient`, and introduce resource enums for the endpoints that should refresh local records.

```text
Storage-only:
    Koma + KomaMacros + KomaSQLite

Storage plus REST refresh:
    Koma + KomaMacros + KomaSQLite + KomaHTTP
```

This modularity is intentional. Koma's SQLite ORM is useful by itself; the resource layer builds on top of the same records and store.
