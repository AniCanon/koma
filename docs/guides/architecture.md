# Architecture

Koma is a small repository-friendly SQLite ORM, data mapper, and request refresh layer. It is not Active Record, not a Firebase-style whole-database sync engine, and not just a REST client.

The public API should feel high level, but the runtime stays close to typed records, HTTP requests, and SQLite statements. The performance goal is to stay close to raw SQLite on common app workloads, not to replace hand-written SQL in every corner case.

The SQLite ORM is usable on its own. The resource and HTTP layers are additive.

```text
Storage-only mode:
    Koma + KomaMacros + KomaSQLite

Storage plus REST refresh:
    Koma + KomaMacros + KomaSQLite + KomaHTTP
```

## Responsibility Matrix

| Piece | Owned by | Responsibility | Does not do |
| --- | --- | --- | --- |
| Transport model | App/backend contract | Codable shape returned by REST | Own persistence or app relationships |
| Record | Koma schema layer | Normalized SQLite row and transport mapping | Save itself or call the network |
| Store | Koma runtime | Local persistence, transactions, migrations, queries | Know product workflows |
| Resource | Koma macro/client layer | Describe REST routes, cache, refresh, adapters | Replace app repositories |
| Adapter | App/Koma boundary | Persist envelopes, pagination, multi-table responses | Store opaque payload blobs |
| Model | App read layer | Hydrated app-facing data and relationships | Become the storage truth |
| Graph context | Koma runtime | Memoize and batch relation loading | Define business rules |
| Join query | Koma query layer | Filter base rows through related tables | Hydrate object graphs |
| KomaClient | Composition root/runtime | Hold store, transport, plugins, codecs, scheduler | Hide global app state |
| Repository | App layer | Product workflow API for features/tests | Leak storage details into UI |

## Data Lifecycle

```text
REST response
    |
    v
Transport model
    |
    v
Generated resource client
    |
    v
Mapper or adapter
    |
    v
Record
    |
    v
KomaStore / SQLite
    |
    v
Query
    |
    v
Hydrated model
    |
    v
App repository
    |
    v
Feature UI
```

Reads can also start locally. A repository can query the store with `.localOnly` or `koma.query(Model.self)` without touching the network.

## Which Type Do I Create?

Use a transport model when you need to decode the backend response.

```swift
struct Project: Codable, Sendable {
    var id: String
    var name: String
    var slug: String
    var deletedAt: Date?
}
```

Use a record when you need normalized local storage.

```swift
@KomaEntity(table: "projects", as: Project.self)
struct ProjectRecord: KomaRemoteRecord {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String
    var deletedAt: Date?
}
```

Use an explicit mapper when the backend shape differs from the table shape.

```swift
@KomaEntity(table: "projects", as: ProjectDTO.self)
struct ProjectRecord: KomaRemoteRecord {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String

    init(remote dto: ProjectDTO) {
        id = dto.projectId
        name = dto.title
        slug = dto.links.slug
    }

    var remoteValue: ProjectDTO {
        ProjectDTO(projectId: id, title: name, links: .init(slug: slug))
    }
}
```

Use an adapter when the response is an envelope, pagination page, or multi-table payload.

```swift
@KomaRoute(.get(as: ProjectPage.self), adapter: ProjectPageAdapter.self)
case list(ProjectListParams = .init())
```

Use a hydrated model when app code wants relationship-aware read models.

```swift
@KomaModel(record: ProjectRecord.self, relations: ProjectRelations.self)
struct ProjectModel {
    var id: String
    var name: String
    var slug: String
    var deletedAt: Date?
}
```

Use a repository when a feature needs a stable product API.

```swift
protocol ProjectServing: Sendable {
    func listProjects(search: String?) async throws -> [ProjectModel]
    func project(id: String) async throws -> ProjectModel
}
```

## Records Are the Storage Truth

Records are normalized table rows. They are not view models and they are not raw REST payloads.

```swift
@KomaEntity(table: "projects", as: Project.self)
struct ProjectRecord: KomaRemoteRecord {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String
    var deletedAt: Date?
}
```

When a transport model has the same shape as the record, `as:` generates the default mapping. If the transport shape differs, the record can provide its own mapper or the resource can use an adapter.

Koma is not an Active Record ORM. Records do not save themselves, open network requests, or discover relationships through hidden global state. They are passive, sendable values with generated schema metadata and mapping support. The store, client, resource, adapter, and repository layers own behavior.

## Resources Refresh Data

Resource enums describe concrete HTTP operations. A fetch with `.networkFirstFallback` performs the request, persists typed records through the mapper or adapter, and then reads from local storage.

```swift
let snapshot = try await ProjectResources.client(in: koma)
    .list(ProjectListParams(search: "akira"))
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .fetch(policy: .networkFirstFallback)
```

This is request-oriented refresh, not whole-database sync. Koma keeps parameterized requests such as `projects/123` refreshable without needing a backend sync protocol.

## Models Hydrate App Data

Hydrated models sit above records for app-facing reads and relationships.

```text
ProjectModel
    |
    +--> ProjectRecord
    |
    +--> KomaGraphContext
            |
            +--> lazy relationship fetch
            +--> included relationship cache
```

`include(...)` batch-loads relationships and stores them in the graph context. Lazy relation fetches use the same query engine and can add filters.

```swift
let projects = try await koma.query(ProjectModel.self)
    .where { $0.deletedAt == nil }
    .include(\.characters)
    .fetch()

let activeCharacters = try await projects[0].characters
    .where { $0.deletedAt == nil }
    .fetch()
```

Joins are available when the base result should be filtered by a related table:

```swift
let projects = try await koma.query(ProjectModel.self)
    .join(CharacterRecord.self) { $0.id == $1.projectId }
    .where(CharacterRecord.self) { $0.name.hasPrefix("A") }
    .fetch()
```

The distinction is intentional: `include(...)` hydrates relationship data, while `join(...)` narrows the base query.

## Platform Ownership

Koma owns storage, resources, refresh registration, and request execution. The host app owns process lifetime, dependency injection, iOS `BGTaskScheduler`, Android `WorkManager`, and auth token storage.

At app launch or background wake, re-register handlers for the requests the app cares about, then ask Koma to refresh due work.

```swift
try await repository.restoreRefreshHandlers(recentProjectIDs: recentProjectIDs)
let results = try await koma.refreshDueRegistrations()
```

This boundary keeps security explicit: Koma stores request intent and cache metadata, not bearer tokens, cookies, or opaque response blobs.
