# Philosophy

Koma was created by AniCanon to make offline read-first app data practical across iOS and Android Swift.

AniCanon needs project, character, asset, and production data to remain useful when the device is offline or the app is waking in the background. At the same time, turning every backend endpoint into a full sync endpoint too early creates a heavy contract: cursors, conflict resolution, outbox writes, auth renewal, tenant scoping, tombstones, and server-side merge behavior all have to be correct.

Koma starts with a narrower promise: use the REST requests the app already has, persist their typed records locally, and let the app re-run important requests when the platform gives it time.

## What Koma Optimizes For

- Offline reads should be the default experience.
- App code should query typed local data, not raw response payloads.
- REST refresh should normalize into records before the app reads.
- Parameterized requests such as `projects/123` should be refreshable without whole-database sync.
- Auth and platform scheduling should stay in the host app, where product policy belongs.
- The public API should stay clean while macros and stores handle repetitive low-level work.

## What Koma Avoids

Koma does not store opaque REST payload blobs as the main persistence model. It does not pretend to solve backend sync without a backend contract. It does not hide auth tokens in a scheduler. It does not require app features to depend directly on storage internals.

Outbox writes, conflict resolution, cursor sync, and merge policies are intentionally deferred. They belong on top of a clear server contract, not inside a generic local cache.

## Architecture Style

Koma is not Active Record.

In Active Record, model objects usually own persistence methods such as `save`, `delete`, or relationship loading. Koma keeps those responsibilities separate:

- Records are passive value types that describe SQLite storage and transport mapping.
- `KomaStore` owns local persistence.
- Resource clients own request execution and refresh policy.
- Adapters own complex response persistence.
- Hydrated models own app-facing relationship access through a graph context.
- App repositories own product workflows and dependency injection.

This is closer to a repository-friendly data mapper style than Active Record. Koma can generate boring mapping code, but it does not make records responsible for the whole data lifecycle.

## Request-Oriented Refresh

Koma refreshes requests, not the whole database.

```swift
let project = try await ProjectResources.client(in: koma)
    .detail(projectId: "123")
    .keepFresh(.whileRecentlyViewed(days: 7, staleAfter: .minutes(15), userScope: user.id))
    .fetch(policy: .networkFirstFallback)
```

That call stores refresh intent for the concrete request: method, path, query parameters, cache namespace, user scope, and timing policy. It does not store bearer tokens, cookies, or raw payloads.

On iOS or Android, the host app schedules background work with native platform APIs. When the app wakes, it re-registers the safe handlers it cares about and asks Koma to refresh due work.

```swift
try await repository.restoreRefreshHandlers(recentProjectIDs: recentProjectIDs)
let results = try await koma.refreshDueRegistrations()
```

This gives apps a useful offline layer now, while leaving full sync for the moment the backend and product rules are ready.
