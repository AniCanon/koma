# Storage-Only Mode

Koma can be used as a small typed SQLite ORM without the network layer.

Use this mode when an app already has its own networking, does not need REST-backed refresh, or only wants a local database with typed queries, writes, migrations, local search, and optional hydrated models. Koma should be read as an ergonomic layer close to raw SQLite performance, not as a replacement for every hand-written SQL workload.

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

## Add Raw SQL and Local Search

Storage-only apps can use Koma's SQLite escape hatches without adopting the REST layer.

Use `rawQuery` for custom SQLite and `rawExecute` for custom writes. When a raw write changes tables that live observations depend on, pass the table names through `invalidating:`.

```swift
let rows = try await store.rawQuery(
    "SELECT id, name FROM projects WHERE name LIKE ? ORDER BY name LIMIT ?",
    arguments: ["A%", 20]
)

try await store.rawExecute(
    "UPDATE projects SET name = ? WHERE id = ?",
    arguments: ["Akira Boards", "1"],
    invalidating: [ProjectRecord.komaTableName]
)
```

For local search, Koma can maintain FTS5 indexes and vector sidecar indexes while still hydrating typed records.

```swift
try await store.createFullTextIndex(for: ProjectRecord.self, indexing: \.name)

let keywordMatches = try await store.fullTextSearch(
    ProjectRecord.self,
    matching: "akira",
    limit: 20
)
```

For embedding search, store vectors as `Data` with `KomaVector.encode`.

```swift
try await store.createQuantizedVectorIndex(for: MemoryRecord.self, on: \.embedding)

let nearest = try await store.nearestQuantized(
    MemoryRecord.self,
    to: queryEmbedding,
    on: \.embedding,
    limit: 20,
    overfetch: 10
)
```

Quantized vector search is a recall optimization. It uses the int8 sidecar to choose candidates quickly, then reranks candidates with full-precision cosine before returning typed records.

## Add Network Later

The network layer is additive. A storage-only app can later add `KomaHTTP`, create a `KomaClient`, and introduce resource enums for the endpoints that should refresh local records.

```text
Storage-only:
    Koma + KomaMacros + KomaSQLite

Storage plus REST refresh:
    Koma + KomaMacros + KomaSQLite + KomaHTTP
```

This modularity is intentional. Koma's SQLite ORM is useful by itself; the resource layer builds on top of the same records and store.
