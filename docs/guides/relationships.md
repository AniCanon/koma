# Relationships

Hydrated models provide app-facing access to normalized records.

```swift
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

        @KomaHasOne(
            ProjectProfileRecord.self,
            local: \ProjectRecord.Columns.id,
            foreign: \ProjectProfileRecord.Columns.projectId,
            model: ProjectProfileModel.self
        )
        case profile
    }
}
```

Koma generates a lazy relation handle for each relation. Fetching is explicit:

```swift
let characters = try await project.characters.fetch()
```

For simple access, relation handles also support `callAsFunction()`:

```swift
let characters = try await project.characters()
```

To-one relationships return an optional model:

```swift
let profile = try await project.profile.fetch()
let sameProfile = try await project.profile()
```

Filtering remains SQL-backed because the relation is query-like:

```swift
let activeCharacters = try await project.characters
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .fetch()
```

Inverse to-one relationships use `@KomaBelongsTo`:

```swift
@KomaModel(record: CharacterRecord.self)
struct CharacterModel {
    var id: String
    var projectId: String
    var name: String

    enum Relations {
        @KomaBelongsTo(
            ProjectRecord.self,
            local: \CharacterRecord.Columns.projectId,
            foreign: \ProjectRecord.Columns.id,
            model: ProjectModel.self
        )
        case project
    }
}

let project = try await character.project()
```

Because relation properties are not `async throws`, eager loading can use key paths:

```swift
let projects = try await koma.query(ProjectModel.self)
    .where { $0.deletedAt == nil }
    .include(\.characters)
    .fetch()
```

Included relations are served from the graph context cache. Repeated unfiltered access is memoized.

Koma uses batched secondary queries for `.include(...)` because that keeps hydration predictable and avoids N+1 reads. Use query joins when you need to filter a base result by a related table:

```swift
let projects = try await store.query(ProjectModel.self)
    .join(CharacterRecord.self) { $0.id == $1.projectId }
    .where(CharacterRecord.self) { $0.deletedAt == nil }
    .fetch()
```

For `@KomaHasOne`, Koma expects the database shape to make the relation unique. If multiple related rows match, the first row returned by SQLite is used.
