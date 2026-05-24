# Getting Started

Koma has two entry points:

- Storage-only mode for a typed SQLite ORM.
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

let store = try await SQLiteKomaStore(path: databaseURL.path)

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

Create a SQLite store, configure a client, and query through macro-expanded resources or the store directly.

```swift
let store = try await SQLiteKomaStore(path: databaseURL.path)

let koma = KomaClient(
    baseURL: apiBaseURL,
    store: store,
    transport: URLSessionKomaTransport(),
    plugins: [
        KomaBearerAuthPlugin { try await tokenProvider.token() },
        KomaRetryPlugin(maxAttempts: 3)
    ]
)
```

Use constructor injection at app boundaries. In tests or scoped jobs, `KomaContext.withClient(_:_:)` can provide a task-local client.

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
