# Scheduled Refresh

Koma schedules concrete refreshable requests, not whole-database sync.

Mark safe read operations as refreshable:

```swift
@KomaRoute(
    .get("{projectId}", as: Project.self),
    cache: .entity("projects", staleAfter: .minutes(15)),
    refresh: .allowed
)
case detail(projectId: String)
```

Attach refresh intent to the same fetch chain:

```swift
let project = try await ProjectResources.client(in: koma)
    .detail(projectId: "123")
    .keepFresh(.whileRecentlyViewed(days: 7, staleAfter: .minutes(15), userScope: user.id))
    .fetch(policy: .networkFirstFallback)
```

Koma stores the operation, concrete path, query parameters, cache namespace, user scope, and policy. It does not store authorization headers, cookies, bearer tokens, or raw response payloads.

Refresh handlers are in-memory closures. After app launch, process restart, or Android/iOS background wake, re-register the routes your app wants to keep fresh before asking Koma to refresh due work:

```swift
try await repository.restoreRefreshHandlers(recentProjectIDs: recentProjectIDs)
let results = try await koma.refreshDueRegistrations()
```

When handlers are already registered in the current process, the host platform can call:

```swift
let results = try await koma.refreshDueRegistrations()
```

iOS and Android should schedule wakeups with their native schedulers. Koma owns the request registry and refresh execution; the app owns platform scheduling.

Use:

```swift
try await koma.clearRefreshRegistrations(userScope: user.id)
```

when a user logs out or a tenant changes.
