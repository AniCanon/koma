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

## Parameter Labels

A parameter can be declared unlabeled in any position with `_ name: Type`. The external label is dropped from the generated call, and the local name binds path placeholders, query items, and the request body:

```swift
@KomaRoute(.get("{projectId}/factions", as: [Faction].self), cache: .collection("factions"))
case factions(projectId: String, _ params: FactionParams = .init())
```

```swift
let snapshot = try await FactionResources.client(in: koma)
    .factions(projectId: "p-1", FactionParams(search: "sun"))
    .fetch(policy: .networkFirstFallback)
```

A parameter named `body` carries the request body; every other non-path parameter is encoded as a query item on `GET`. Defaults declared on the case are preserved on the generated method.

## Cache Namespaces

A `cache:` namespace may contain `{placeholder}` segments that match the route's path placeholders. They resolve at runtime from the request's path values, so a nested collection can be namespaced per parent instead of sharing one global name:

```swift
@KomaRoute(
    .get("{projectId}/characters", as: [Character].self),
    cache: .collection("projects/{projectId}/characters"),
    refresh: .allowed
)
case characters(projectId: String)
// registered namespace: "collection:projects/p-1/characters"
```

Path values are substituted verbatim — a namespace is a storage key, not a URL, so it is not percent encoded. A placeholder with no matching path value stays literal rather than failing, exactly as an unresolved path placeholder does. A namespace without placeholders is stored as written.

## Request Headers

`KomaOperation` takes optional per-operation headers. They apply to fetches and commands alike, and are the way to send a body Koma does not encode itself, such as multipart form data:

```swift
let ticket: UploadTicket = try await KomaReturningCommand(
    client: koma,
    operation: KomaOperation(
        name: "uploadAsset",
        method: .post,
        path: "projects/{projectId}/assets",
        pathValues: ["projectId": projectId],
        body: KomaRequestBody { multipartData },
        headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"]
    )
).perform()
```

Header precedence, lowest to highest:

1. Koma's defaults — `Accept: application/json`, plus `Content-Type: application/json` when the operation has a body.
2. The operation's `headers`, which override those defaults.
3. The client's plugins, which run last and win over both. An operation cannot strip the `Authorization` header a `.bearerAuth` plugin sets, or otherwise opt itself out of the pipeline.

Header names are matched exactly, so `Content-Type` and `content-type` are two different entries and both would be sent.

A route declares headers in two places, by whether their values are known at compile time. `@KomaRoute(headers:)` carries the fixed ones. A `headers: [String: String]` case parameter carries the ones a call computes, such as a multipart boundary; it is excluded from query items, exactly as `body` is, and merged over the route's fixed headers, so a duplicate name takes the call's value:

```swift
@KomaRoute(
    .post("{projectId}/assets", returning: UploadTicket.self),
    headers: ["X-Upload-Protocol": "multipart"]
)
case uploadAsset(projectId: String, headers: [String: String], body: Data)
```

```swift
let ticket = try await AssetResources.client(in: koma)
    .uploadAsset(
        projectId: "p-1",
        headers: ["Content-Type": "multipart/form-data; boundary=\(boundary)"],
        body: multipartData
    )
    .perform()
```

A `body` parameter typed `Data` or `KomaRequestBody` is sent as written rather than passed through the JSON encoder — `Data` is `Encodable`, so encoding it would send a base64 string instead of the bytes. Every other body type is JSON encoded as before.

## Commands

A fetch is the read side: it refreshes an endpoint, persists typed records, and reads back from the store. Writes go through commands (CQRS: queries read, commands write). Both run the same plugin pipeline as a fetch, so auth, retry, and logging apply.

`KomaCommand` performs a write and evicts local rows once it succeeds, without decoding a response body. A `404` is treated as success so deletes stay idempotent; pass `notFoundIsSuccess: false` to opt out.

```swift
try await KomaCommand<CharacterRecord>(
    client: koma,
    operation: KomaOperation(
        name: "deleteCharacter",
        method: .delete,
        path: "projects/{projectId}/characters/{characterId}",
        pathValues: ["projectId": projectId, "characterId": characterId]
    ),
    evicting: [characterId]
).perform()
```

`KomaReturningCommand` is the returning form: it sends the request and decodes the response with the client's `jsonDecoder`. Use it for writes whose response is not stored data — a job handle, an analysis payload, a presigned upload. It needs no `Record` type because nothing is persisted.

```swift
let job: Job = try await KomaReturningCommand(
    client: koma,
    operation: KomaOperation(
        name: "generateImage",
        method: .post,
        path: "projects/{projectId}/images",
        pathValues: ["projectId": projectId],
        body: KomaRequestBody { try koma.jsonEncoder.encode(request) }
    )
).perform()
```

The response must carry a JSON body decodable as the requested type; an empty or `204` response has nothing to return, so use `KomaCommand` for those. A non-2xx status throws `KomaHTTPError.invalidResponse(statusCode:body:)` before any decoding is attempted, and `404` is a plain failure here with no absorption.

When the response body does contain records worth keeping, do not decode it with a returning command. Run the operation through a resource route and `fetch(...)` — with an [adapter](adapters.md) if the shape is an envelope — so the records are persisted once, by the path that owns persistence.

## Returning Routes

A resource route declares a returning command by spelling its response `returning:` instead of `as:`. The two labels are the read/write split in the route grammar: `as:` decodes into the namespace's record type and generates a `KomaFetch`, `returning:` generates a `KomaReturningCommand` and persists nothing.

```swift
@KomaResource(basePath: "projects")
enum RenderResources {
    @KomaRoute(.post("{projectId}/renders", returning: RenderJob.self))
    case render(projectId: String, body: RenderRequest, dryRun: Bool = false)
}
```

```swift
let job = try await RenderResources.client(in: koma)
    .render(projectId: "p-1", body: RenderRequest(prompt: "sunset"), dryRun: true)
    .perform()
// POST projects/p-1/renders?dryRun=true
```

The generated method mirrors a fetch method, down to path placeholders, the `body` parameter, and defaults:

```swift
public func render(projectId: String, body: RenderRequest, dryRun: Bool = false) -> KomaReturningCommand<RenderJob> {
    KomaReturningCommand(
        client: self.koma,
        operation: KomaOperation(
            name: "render",
            method: .post,
            path: KomaPath.join("projects", "{projectId}/renders"),
            queryItems: [KomaQueryEncoder.queryItem(name: "dryRun", value: dryRun, encoder: self.koma.jsonEncoder)].compactMap { $0 },
            pathValues: ["projectId": String(describing: projectId)],
            body: KomaRequestBody { ... }
        ),
        value: RenderJob.self
    )
}
```

Three differences from an `as:` route:

- `cache:`, `adapter:`, and `refresh:` are not generated. Nothing is stored, so there is no local copy to name, adapt, or keep fresh; passing them to a returning route has no effect.
- Parameters that are neither path placeholders nor `body` nor `headers` become query items whatever the method, not on `GET` alone. A write's leftover parameters have nowhere else to go.
- `GET` is allowed a `returning:` response too. The discriminator is the response, not the verb: a `GET` that answers with something the store does not own — server capabilities, a presigned URL — would otherwise need a record type invented for it.

A namespace of returning routes stores nothing, so `@KomaResource` may omit `record:`:

```swift
@KomaResource(basePath: "projects")
enum RenderResources { ... }
```

`record:` stays required as soon as one route in the namespace is an `as:` route; omitting it there is a compile-time error naming the route that needs it. A namespace may mix both kinds freely.

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
