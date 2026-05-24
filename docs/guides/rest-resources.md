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
