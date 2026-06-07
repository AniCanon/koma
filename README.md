<p align="center">
  <img src="assets/koma-logo.png" alt="Koma" width="420">
</p>

# Koma

Koma is a small Swift 6.3 SQLite ORM and offline refresh layer created by AniCanon for iOS and Android Swift. It keeps app code typed and repository-friendly while staying close to raw SQLite performance for local storage, search, and refresh workloads.

Koma stores normalized records, not opaque REST payload blobs. The first goal is offline read-first data access; outbox writes, cursor sync, conflict resolution, and backend-specific sync protocols are intentionally deferred.

You can use Koma in storage-only mode as a typed SQLite ORM. The network/resource layer is optional and additive.

## What Koma Is

Koma is a local-first data layer for Swift apps that need the same storage code on iOS and Android Swift. It gives you a compact typed SQLite ORM, macro-generated records and REST resources, relationship-aware queries, migrations, request refresh policies, auth plugins, retry plugins, and testable dependency injection.

Koma is not a backend, a global object graph, a whole-database sync product, or a replacement for raw SQLite in every possible workload. Instead, it gives application repositories a small ORM that is close to raw SQLite on measured paths, plus escape hatches for custom SQL when an app needs them.

## Why Koma

AniCanon needed reliable offline data without forcing every backend endpoint to become a full sync contract. Whole-database sync, conflict resolution, cursor ownership, and secure background auth are product-specific problems; pretending they are generic too early makes both client and backend architecture harder to maintain.

Koma takes a smaller, practical stance: model the REST requests the app already makes, persist their typed records locally, and let the app keep important parameterized requests fresh. It gives repositories a stable local-first data layer while leaving true sync protocols to the moment the backend contract is ready.

Architecturally, Koma is not Active Record. Records are value types that describe storage shape and mapping. They do not save themselves, fetch relationships by hidden globals, or own network calls. Persistence lives behind `KomaStore`, request refresh lives behind generated resource clients, and app features should still depend on repository or service protocols.

The performance goal is not to beat hand-written SQLite in every microbenchmark. The goal is to make the common app-facing API small and typed while staying close enough to raw SQLite that teams do not have to choose between ergonomics and local performance.

## Packages

- `Koma`: macro declarations, runtime core, query API, resources, plugins, snapshots, and store protocols.
- `KomaSQLite`: SQLite-backed `KomaStore` using the bundled SQLite amalgamation.
- `KomaHTTP`: `URLSession` transport for REST APIs.
- `KomaTesting`: test utilities such as fake transports.
- `KomaMacros`: deprecated compatibility module that re-exports `Koma`.

## Documentation

The human-readable handbook lives in [docs/README.md](docs/README.md). It covers philosophy, architecture, examples, guides, and benchmark methodology as plain Markdown.

DocC is reserved for Swift API reference. Its source catalog lives at `docs/Koma.docc`, and rendered output is generated under `.build` by `scripts/docs.sh`.

## Examples

Buildable examples live in `Examples/`:

- `Examples/ProjectBrowser`: end-to-end repository sample with entities, relationships, REST resources, parameterized refresh registration, dependency injection, and tests.

Run all examples with:

```sh
scripts/examples.sh
```

## Storage-Only ORM

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

let projects = try await store.query(ProjectRecord.self)
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .fetch()
```

For this mode, depend on `Koma` and `KomaSQLite`. Add `KomaHTTP` only when you want REST-backed refresh. See [Storage-Only Mode](docs/guides/storage-only.md).

## Raw SQL, FTS, and Vector Search

Koma SQLite includes an escape hatch for custom SQL and local search workloads that need SQLite features beyond the typed query builder.

```swift
let rows = try await store.rawQuery(
    """
    SELECT m.id, bm25(memories_fts) AS rank
    FROM memories AS m
    JOIN memories_fts ON memories_fts.rowid = m.rowid
    WHERE memories_fts MATCH ?
    """,
    arguments: ["embeddings"]
)

let id = try rows[0].string("id")
```

Raw writes can invalidate live observations when you tell Koma which tables changed:

```swift
try await store.rawExecute(
    "UPDATE memories SET content = ? WHERE id = ?",
    arguments: ["semantic search note", "1"],
    invalidating: [MemoryRecord.komaTableName]
)
```

For typed local search, create an FTS5 index and store embeddings as `Data` with `KomaVector.encode`:

```swift
try await store.createFullTextIndex(for: MemoryRecord.self, indexing: \.content)

let keyword = try await store.fullTextSearch(
    MemoryRecord.self,
    matching: "embeddings",
    limit: 20
)

let exact = try await store.nearest(
    MemoryRecord.self,
    to: queryEmbedding,
    on: \.embedding,
    limit: 20
)
```

For larger local corpora, add the trigger-maintained int8 sidecar index and use quantized recall followed by exact reranking:

```swift
try await store.createQuantizedVectorIndex(for: MemoryRecord.self, on: \.embedding)

let fast = try await store.nearestQuantized(
    MemoryRecord.self,
    to: queryEmbedding,
    on: \.embedding,
    limit: 20,
    overfetch: 10
)

let hybrid = try await store.hybridSearch(
    MemoryRecord.self,
    matching: "embeddings",
    near: queryEmbedding,
    on: \.embedding,
    identifiedBy: \.id,
    vectorSearch: .quantized(overfetch: 10)
)
```

## Quick Start

For a REST-backed offline app, create one SQLite-backed client at app startup and inject it into repositories or feature clients:

```swift
let koma = try await KomaClient.sqlite(
    database: .applicationSupport("AniCanon.sqlite", appDirectory: "AniCanon"),
    schema: KomaSchema(modules: [
        ProjectSchema.self,
        CharacterSchema.self
    ]),
    baseURL: URL(string: "https://api.example.com/v1")!,
    plugins: [
        KomaBearerAuthPlugin { try await tokenProvider.token() },
        KomaRetryPlugin(maxAttempts: 2)
    ]
)
```

See [App Startup](docs/guides/app-startup.md) for fuller iOS and Android host examples.

Android apps should pass an explicit path from `Context` into their shared Swift runtime:

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

## Resource API

```swift
import Koma

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
```

The macro generates a nested `Client`:

```swift
let projects = ProjectResources.client(in: koma)

let snapshot = try await projects.list()
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .fetch(policy: .networkFirstFallback)
```

Resource fetches are database-first when observed. The default observation emits the local value, refreshes once, emits the refreshed local value, then completes. Use live mode when a screen should stay attached to local table changes:

```swift
for await snapshot in projects.list()
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .observe(mode: .live)
{
    render(snapshot.value)
}
```

`koma.resource(ProjectResources.self)` is also supported.

For scoped code where passing `koma` everywhere adds noise, use the task-local context:

```swift
try await KomaContext.withClient(koma) {
    let snapshot = try await ProjectResources.client()
        .list()
        .where { $0.deletedAt == nil }
        .fetch(policy: .networkFirstFallback)
}
```

Use this as a scoped override for tests, previews, jobs, or request handlers. Prefer explicit constructor injection at app boundaries.

## Model Queries and Relationships

```swift
let projects = try await koma.query(ProjectModel.self)
    .where { $0.deletedAt == nil }
    .include(\.characters)
    .fetch()

let characters = try await projects[0].characters.fetch()
let profile = try await projects[0].profile()
let active = try await projects[0].characters.where { $0.deletedAt == nil }.fetch()
```

Relationship properties are lazy relation handles. Use `.fetch()` to execute, or `project.characters()` as shorthand for an unfiltered relation fetch.

Queries also support joins when you want to filter the base result by a related table:

```swift
let projects = try await koma.query(ProjectModel.self)
    .join(CharacterRecord.self) { $0.id == $1.projectId }
    .where(CharacterRecord.self) { $0.name.hasPrefix("A") }
    .fetch()
```

Outer joins use named methods:

```swift
let projectsWithoutCharacters = try await koma.query(ProjectModel.self)
    .leftJoin(CharacterRecord.self) { $0.id == $1.projectId }
    .where(CharacterRecord.self) { $0.id.isNull() }
    .fetch()
```

## Scheduled Refresh

```swift
@KomaRoute(
    .get("{projectId}", as: Project.self),
    cache: .entity("projects", staleAfter: .minutes(15)),
    refresh: .allowed
)
case detail(projectId: String)

let snapshot = try await ProjectResources.client(in: koma)
    .detail(projectId: "123")
    .keepFresh(.whileRecentlyViewed(days: 7, staleAfter: .minutes(15), userScope: user.id))
    .fetch(policy: .networkFirstFallback)
```

Koma stores refresh intent for the concrete request, not bearer tokens or raw payloads. Platform schedulers can later re-register refresh handlers and call `try await koma.refreshDueRegistrations()`.

## Entity API

```swift
import Koma

@KomaEntity(table: "projects", as: Project.self)
struct ProjectRecord: KomaRemoteRecord {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String
    var deletedAt: Date?
}
```

Stored properties become columns by default. Computed read-only properties are ignored. Add `@KomaIgnore` to explicitly exclude a stored property. If the transport model has matching property names, `as:` generates the default mapping; write `init(remote:)` and `remoteValue` only for custom shapes.

## Migrations

Koma handles additive schema changes automatically when a new stored property becomes a column. For structural changes, split migrations into small packs near the feature that owns the records:

```swift
enum ProjectMigrations: KomaMigrationPack {
    static let namespace = "projects"

    static let migrations = [
        Migration(1, 2) {
            RenameColumn(ProjectRecord.self, from: "title", to: \.name)
            AddIndex(ProjectRecord.self, \.slug, unique: true)
        },
    ]
}

let schema = KomaSchema(
    entities: [ProjectRecord.self],
    migrationPacks: [ProjectMigrations.self]
)

let store = try await SQLiteKomaStore(path: databaseURL.path, schema: schema)
```

Fresh installs create the latest schema directly. Existing databases with user tables and no Koma migration metadata start at the first migration version for each pack.

## Initialization

```swift
import Koma
import KomaHTTP
import KomaSQLite

let store = try await SQLiteKomaStore(path: databaseURL.path, schema: schema)

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

`KomaClient` is the runtime container: create it once at the app composition root, then inject it into repositories, use cases, or dependency values. This keeps Koma testable like Point-Free style clients and avoids Firebase-style hidden global state by default.

For a SwiftUI app, hold the configured client in app state or a dependency container. For TCA, register the feature clients that depend on Koma in `DependencyValues`; the public features should depend on app clients, not directly on Koma.

Read policies:

- `.localOnly`: read SQLite only.
- `.networkFirstFallback`: refresh from REST, persist normalized records, then read local; if the network fails, return cached local data when available.
- `.localThenRefresh`: available through `observe`; emits cached data first and then refreshed data.

## SwiftPM

```swift
.package(url: "https://github.com/AniCanon/koma.git", from: "0.2.0")
```

Storage-only:

```swift
.product(name: "Koma", package: "koma"),
.product(name: "KomaSQLite", package: "koma")
```

Storage plus REST refresh:

```swift
.product(name: "Koma", package: "koma"),
.product(name: "KomaSQLite", package: "koma"),
.product(name: "KomaHTTP", package: "koma")
```

The macro plugin is host-built. Macro declarations are exported from `Koma`; the older `KomaMacros` product is kept as a deprecated compatibility re-export. Runtime targets are designed to compile for Android Swift as well as Apple platforms.

## Development

```sh
swift test
scripts/lint.sh
scripts/format.sh
scripts/examples.sh
scripts/docs.sh
scripts/docs-preview.sh
```

Install the lint tools with:

```sh
brew install swiftformat swiftlint
```

## Benchmarks

Koma includes a benchmark suite for storage, local search, JSON, resource-pipeline, and HTTP-adapter performance:

```sh
scripts/benchmark.sh
scripts/benchmark-official.sh .benchmark-results/local-koma
scripts/benchmark-android.sh .benchmark-results/local-android
```

Benchmark dependencies are opt-in. The package only resolves Alamofire, Moya, Apollo, GRDB, and `swift-benchmark` when `KOMA_ENABLE_BENCHMARKS=1`; normal app consumers do not download them. SwiftData benchmarks are additionally opt-in for Xcode toolchains because the SwiftData model macro is not available in the open-source CLI toolchain by default.

Lower is better. Read the storage and search tables as a closeness-to-raw check, not as a claim that Koma replaces hand-written SQLite everywhere. The fresh Apple/Darwin tables below are p50 wall-clock clean-branch numbers captured on June 5, 2026 with Apple Swift 6.3 on Darwin 25.5.0 arm64. Artifact: `.benchmark-results/feat-sqlite-raw-sql-clean-20260605`. Android emulator numbers remain the May 24, 2026 smoke baseline.

Apple/Darwin storage and local resources:

| Operation | Koma | Raw SQLite | GRDB | Core Data |
| --- | ---: | ---: | ---: | ---: |
| Open + ensure schema | 0.866 ms | n/a | 0.344 ms | 1.255 ms |
| Upsert or insert 1k records | 1.532 ms | 1.789 ms | 7.938 ms | 6.996 ms |
| Steady upsert 1k | 1.546 ms | n/a | n/a | n/a |
| Observed upsert 1k + refetch | 1.707 ms | n/a | n/a | n/a |
| Fused JSON upsert 1k | 1.693 ms | n/a | n/a | n/a |
| Filtered fetch 10k, limit 100 | 0.284 ms | 0.283 ms | 0.344 ms | 0.537 ms |
| Inner join filter 10k, limit 100 | 4.461 ms | 4.641 ms | n/a | n/a |
| Right join matched 10k, limit 100 | 5.030 ms | 4.530 ms | n/a | n/a |
| Left join missing 10k, limit 100 | 7.053 ms | 8.057 ms | n/a | n/a |
| Resource local-only fetch 10k, limit 100 | 0.299 ms | n/a | n/a | n/a |

Android emulator storage:

| Operation | Koma | Raw SQLite | GRDB | SQLite.swift |
| --- | ---: | ---: | ---: | ---: |
| Open + ensure schema | 4.432 ms | 4.540 ms | 1.939 ms | 4.800 ms |
| Upsert 1k records | 5.487 ms | 5.904 ms | 12.054 ms | 6.406 ms |
| Filtered fetch 10k, limit 100 | 0.409 ms | 0.383 ms | 0.484 ms | 0.472 ms |
| Inner join filter 10k, limit 100 | 5.023 ms | 4.963 ms | 4.929 ms | 4.835 ms |

JSON and request pipeline:

| Platform | Operation | Koma | Foundation | YYJSON | Other |
| --- | --- | ---: | ---: | ---: | ---: |
| Apple/Darwin | Decode 1k records | 0.180 ms | 1.351 ms | 0.530 ms | n/a |
| Apple/Darwin | Encode 1k records | 0.348 ms | 1.115 ms | 0.425 ms | n/a |
| Apple/Darwin | Mock GET + decode 1k | 0.270 ms | URLSession + `JSONDecoder` 1.421 ms | n/a | Alamofire 1.516 ms, Moya 1.529 ms, Apollo 39.322 ms |
| Apple/Darwin | Resource `networkFirstFallback` 1k | 2.210 ms | n/a | n/a | URLSession resource 2.570 ms |
| Android emulator | Decode 1k records | 0.420 ms | 1.640 ms | 0.949 ms | n/a |
| Android emulator | Encode 1k records | 0.591 ms | 1.378 ms | 0.739 ms | n/a |

Local search and memory-store validation:

| Operation | Koma exact | Koma quantized | Raw SQLite | Raw quantized | GRDB |
| --- | ---: | ---: | ---: | ---: | ---: |
| FTS5 keyword search 10k | 0.414 ms | n/a | 0.476 ms | n/a | 0.438 ms |
| Vector nearest 10k x 384 | 7.389 ms | 2.384 ms | 7.729 ms | 2.460 ms | 8.774 ms |
| Hybrid keyword + vector 10k x 384 | 7.950 ms | 3.355 ms | 8.634 ms | 3.625 ms | 9.650 ms |

Full methodology and historical runs live in [Benchmark Results](docs/benchmarks/results.md). Each publishable run should include raw output plus metadata for the Koma revision, Swift toolchain, platform, and command.

## License

Koma is released under the MIT license.
