# Project Browser

This sample models an AniCanon-style project browser with offline read-first REST resources and relationships.

It intentionally uses a fake transport so the package can run without a backend. Swap `FakeKomaTransport` for `URLSessionKomaTransport` at the app composition root when connecting to a real API.

## API Shape

```swift
let projects = try await repository.listProjects(search: "akira")

let detail = try await repository.project(id: "project-1")

let activeCharacters = try await detail.characters
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .fetch()
```

Parameterized routes can be kept fresh as concrete requests:

```swift
_ = try await ProjectResources.client(in: koma)
    .detail(projectId: "project-1")
    .keepFresh(.whileRecentlyViewed(days: 7, staleAfter: .minutes(15), userScope: userID))
    .fetch(policy: .networkFirstFallback)
```

Koma stores the route, path values, query parameters, cache namespace, and user scope. It does not store bearer tokens, cookies, or raw response payloads.

## Run

```sh
swift run ProjectBrowser
swift test
```
