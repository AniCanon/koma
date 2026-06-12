# REST Resources

Resource enums describe REST operations. Koma generates a nested client that returns lazy fetch objects.

```swift
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

Use resource fetches for REST-backed refresh and local fallback:

```swift
let snapshot = try await ProjectResources.client(in: koma)
    .list(ProjectListParams(search: "akira"))
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .fetch(policy: .networkFirstFallback)
```

For `GET` operations, a single associated parameter struct is encoded as query items. Path placeholders bind to matching associated-value labels.

## Conditional Requests

When a server returns `ETag` or `Last-Modified` headers, Koma stores the validator per concrete GET and revalidates with `If-None-Match` / `If-Modified-Since` on later refreshes. A `304 Not Modified` skips the response download, the decode, and the upsert; the snapshot is served from the local store, which the server just confirmed is current. This is automatic; opt out per client with `conditionalRequests: .disabled`. Validators clear together with refresh registrations on `clearRefreshRegistrations`.

## Observation

Resource observations are local-store driven. They emit a local snapshot first so a screen can render cached data immediately, then refresh the endpoint and emit again from the store when the refreshed records are persisted.

```swift
for await snapshot in ProjectResources.client(in: koma)
    .list(ProjectListParams(search: "akira"))
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .observe()
{
    render(snapshot.value)
}
```

The default mode is `.once`: local value, one refresh, refreshed local value, then completion. Use `.live` when the caller should stay attached to matching local table changes:

```swift
for await snapshot in ProjectResources.client(in: koma)
    .list()
    .observe(mode: .live)
{
    render(snapshot.value)
}
```

Live observation does not require a separate cached fetch API. Koma observes the local query, starts refresh after the first local emission, coalesces store invalidations, and keeps the public fetch surface centered on `fetch(...)`, `refresh()`, and `observe(...)`.
