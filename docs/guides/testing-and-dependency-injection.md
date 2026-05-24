# Testing and Dependency Injection

Create `KomaClient` at the app composition root and inject app-specific clients into features.

```swift
struct LiveProjectsClient: ProjectsClient {
    let koma: KomaClient

    func listProjects() async throws -> [Project] {
        try await ProjectResources.client(in: self.koma)
            .list()
            .fetch(policy: .networkFirstFallback)
            .value
    }
}
```

Tests can use `KomaTesting` with fake transports and in-process SQLite stores.

```swift
let transport = FakeKomaTransport(responses: [
    KomaResponse(statusCode: 200, body: data)
])

let koma = KomaClient(
    baseURL: URL(string: "https://example.com")!,
    store: store,
    transport: transport
)
```

For scoped overrides, use task-local context:

```swift
try await KomaContext.withClient(koma) {
    try await ProjectResources.client().list().refresh()
}
```

Prefer explicit injection for app code. Use task locals for tests, previews, command handlers, and short-lived override scopes.
