# Adapters

Adapters persist complex REST outputs without saving opaque payload blobs.

Use an adapter when an endpoint returns an envelope, pagination metadata, or records for more than one table.

Records with matching transport models do not need an adapter:

```swift
@KomaEntity(table: "projects", as: Project.self)
struct ProjectRecord: KomaRemoteRecord {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String
    var deletedAt: Date?
}
```

For different field names, provide a mapper on the record:

```swift
@KomaEntity(table: "projects", as: ProjectDTO.self)
struct ProjectRecord: KomaRemoteRecord {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String
    var deletedAt: Date?

    init(remote dto: ProjectDTO) {
        id = dto.projectId
        name = dto.title
        slug = dto.links.slug
        deletedAt = dto.archivedAt
    }

    var remoteValue: ProjectDTO {
        ProjectDTO(
            projectId: id,
            title: name,
            links: .init(slug: slug),
            archivedAt: deletedAt
        )
    }
}
```

## Pagination

```swift
struct ProjectPage: Codable, Sendable {
    var items: [Project]
    var nextCursor: String?
}

struct ProjectListParams: Codable, Sendable {
    var search: String?
    var cursor: String?
}
```

Store page metadata in its own typed table:

```swift
@KomaEntity(table: "project_pages")
struct ProjectPageRecord: KomaEntityRecord {
    @KomaPrimaryKey var id: String
    var nextCursor: String?
    var cachedAt: Date
}
```

Then persist both records and metadata in one transaction:

```swift
enum ProjectPageAdapter: KomaPersistenceAdapter {
    static func persist(
        _ output: ProjectPage,
        context: KomaPersistenceContext,
        store: any KomaStore
    ) async throws {
        let search = context.queryItems.first { $0.name == "search" }?.value ?? ""

        try await store.transaction { tx in
            try await tx.upsert(output.items.map(ProjectRecord.init(remote:)))
            try await tx.upsert([
                ProjectPageRecord(
                    id: "projects:\(search)",
                    nextCursor: output.nextCursor,
                    cachedAt: Date()
                )
            ])
        }
    }
}
```

Attach the adapter to the paginated route:

```swift
@KomaResource(basePath: "projects", record: ProjectRecord.self)
enum ProjectResources {
    @KomaRoute(
        .get(as: ProjectPage.self),
        cache: .collection("projects", staleAfter: .minutes(5)),
        adapter: ProjectPageAdapter.self
    )
    case list(ProjectListParams = .init())
}
```

The repository can refresh a page, then return hydrated local models:

```swift
struct ProjectsRepository {
    let koma: KomaClient

    func firstPage(search: String?) async throws -> [ProjectModel] {
        _ = try await ProjectResources.client(in: koma)
            .list(ProjectListParams(search: search))
            .fetch(policy: .networkFirstFallback)

        return try await koma.query(ProjectModel.self)
            .where { $0.deletedAt == nil }
            .order(by: \.name)
            .limit(50)
            .fetch()
    }

    func nextPage(search: String?) async throws -> [ProjectModel] {
        let pageID = "projects:\(search ?? "")"
        let page = try await koma.query(ProjectPageRecord.self)
            .where { $0.id == pageID }
            .first()

        guard let cursor = page?.nextCursor else {
            return []
        }

        _ = try await ProjectResources.client(in: koma)
            .list(ProjectListParams(search: search, cursor: cursor))
            .fetch(policy: .networkFirstFallback)

        return try await koma.query(ProjectModel.self)
            .where { $0.deletedAt == nil }
            .order(by: \.name)
            .fetch()
    }
}
```

Adapters should persist typed records and typed metadata only. If a backend needs full sync, define a backend contract first and build sync on top of the same storage primitives.
