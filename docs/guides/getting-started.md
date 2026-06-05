# Getting Started

Koma has two entry points:

- Storage-only mode for a small typed SQLite ORM that stays close to raw SQLite performance.
- Storage plus REST refresh for offline read-first networked apps.

## Storage-Only

Use `Koma`, `KomaMacros`, and `KomaSQLite` when you only need local storage.

```swift
@KomaEntity(table: "projects")
struct ProjectRecord: KomaEntityRecord {
    @KomaPrimaryKey var id: String
    var name: String
    var deletedAt: Date?
}

let store = try await SQLiteKomaStore.open(
    database: .applicationSupport("AniCanon.sqlite", appDirectory: "AniCanon")
)

try await store.upsert([
    ProjectRecord(id: "1", name: "Akira Boards", deletedAt: nil)
])

let projects = try await store.query(ProjectRecord.self)
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .fetch()
```

See [Storage-Only Mode](storage-only.md) for the full guide.

## Storage Plus REST Refresh

Create a SQLite-backed client and query through macro-expanded resources or the store directly.

```swift
let koma = try await KomaClient.sqlite(
    database: .applicationSupport("AniCanon.sqlite", appDirectory: "AniCanon"),
    schema: KomaSchema(modules: [
        ProjectSchema.self,
        CharacterSchema.self
    ]),
    baseURL: apiBaseURL,
    plugins: [
        KomaBearerAuthPlugin { try await tokenProvider.token() },
        KomaRetryPlugin(maxAttempts: 3)
    ]
)
```

Use constructor injection at app boundaries. In tests or scoped jobs, `KomaContext.withClient(_:_:)` can provide a task-local client.

For Android Swift, resolve the database path from the Android host app and pass it into the shared Swift layer:

```kotlin
val databaseFile = context.getDatabasePath("koma.sqlite")
databaseFile.parentFile?.mkdirs()

val runtime = SharedRuntime(
    baseURL = BuildConfig.API_BASE_URL,
    databasePath = databaseFile.absolutePath,
)
```

```swift
let koma = try await KomaClient.sqlite(
    database: .path(databasePath),
    schema: appSchema,
    baseURL: baseURL,
    plugins: plugins
)
```

```swift
let snapshot = try await ProjectResources.client(in: koma)
    .list()
    .where { $0.deletedAt == nil }
    .fetch(policy: .networkFirstFallback)
```

For app-facing hydrated models:

```swift
let projects = try await koma.query(ProjectModel.self)
    .where { $0.deletedAt == nil }
    .include(\.characters)
    .fetch()
```
