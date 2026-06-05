# Performance and Benchmarks

Koma benchmarks compare the public API against lower-level storage baselines.

Koma is designed to keep app code high level while moving repetitive work into generated or storage-specific fast paths. The selling point is a small ORM close to raw SQLite performance, not a claim that the ORM replaces hand-written SQL in every workload.

## Why Koma Is Fast

- Entity macros generate table metadata, columns, binders, row readers, and JSON record decoders instead of discovering schema through runtime reflection.
- SQLite writes bind typed values directly and avoid storing opaque REST payload blobs.
- SQLite reads use generated record fast paths for supported scalar columns.
- The optimized JSON path decodes common flat REST responses directly into records and encodes supported record-shaped request bodies without going through the general-purpose encoder.
- Resource refresh can use the fused JSON path to scan response bytes and bind SQLite values without first building an intermediate record array when the caller only needs the persisted result.
- Resource fetches persist normalized records first, then reuse the same local query engine for filtering, sorting, limits, and relationships.
- Live observations use table invalidation plus buffered signals, so repeated writes coalesce while an observer is refetching.
- Relationship `.include(...)` batch-loads related records and avoids N+1 query patterns.
- Raw SQL, FTS5, and vector search APIs stay on the same serialized SQLite actor and reuse generated row hydration instead of forcing users through a separate database stack.
- Exact vector search scans a lean `rowid + embedding` projection, scores `Float64` blobs directly from SQLite row buffers, and hydrates only the winners.
- Quantized vector search uses a trigger-maintained int8 sidecar as a fast pre-filter, then reranks over-fetched candidates with full-precision cosine.
- The HTTP layer stays close to `URLSession`; plugins compose auth, retry, and logging without hiding the transport.

Raw SQLite can still win some narrow microbenchmarks because it has no framework abstraction. Koma's target is to stay close to raw SQLite while preserving a typed, testable API and explicit raw SQL escape hatches.

```sh
scripts/benchmark.sh
scripts/benchmark-official.sh .benchmark-results/local-koma
```

The official script records metadata with each run:

- Koma revision
- Swift toolchain
- platform and CPU
- command
- raw benchmark output

The current suite covers raw SQLite, Koma SQLite, GRDB, Core Data, SwiftData when explicitly enabled from an Xcode toolchain, Koma resource refresh, Koma local resource reads, FTS5, exact vector search, quantized vector search, hybrid search, URLSession, Alamofire, Moya, Apollo, and Koma's optimized JSON record path where the platform supports them.

Relation loading, eager includes, refresh due scans, large `IN` predicates, and migration-heavy workloads are the next benchmark areas to add before quoting broader ORM claims.

Use benchmark results to decide where to optimize internals without changing the public API. The app-facing surface should stay clean; Koma should absorb lower-level storage details.

## Reading Results

Use raw SQLite as the lower-bound storage baseline and read Koma results as closeness-to-raw evidence. Use GRDB as the mature Swift SQLite peer. Treat Core Data and SwiftData as Apple-only comparisons, not Android Swift peers.

For networking, compare transport-only numbers against `URLSession` and full decode paths against URLSession, Alamofire, Moya, and Apollo where each tool's model applies. Koma should be transparent when it is measuring REST and when Apollo is measuring a GraphQL client stack.

Official numbers should quote p50 and p90 from `scripts/benchmark-official.sh`, include the benchmark artifact path, and avoid claims from uncommitted local runs.

## SQLite Search

Koma's search APIs are intended for single-device local memory stores and other app-local corpora:

- `rawQuery` and `rawExecute` expose custom SQLite with typed arguments. Raw writes can pass `invalidating: [tableName]` so live observations refetch without Koma trying to parse arbitrary SQL.
- `createFullTextIndex` builds an external-content FTS5 table, creates insert/update/delete triggers, and rebuilds from existing rows so migrations can add search later.
- `fullTextSearch` returns typed records ranked by FTS5 relevance.
- `nearest` performs exact cosine search over `KomaVector.encode` `Float64` blobs. It scans every matching row, so it is predictable and exact but O(n).
- `createQuantizedVectorIndex` builds a sidecar table named `<table>_<column>_i8`, backfills it, and keeps it current with SQLite triggers.
- `nearestQuantized` scans the int8 sidecar, over-fetches candidates, and reranks those candidates with full-precision cosine before returning typed records.
- `hybridSearch` fuses FTS5 keyword recall and vector recall with reciprocal-rank fusion. Use `vectorSearch: .quantized(overfetch:)` only after creating the quantized vector index.

Quantized search is a recall optimization, not a replacement for exact scoring. Koma uses it to pick candidates quickly and still reports similarities from full-precision reranking.

## Observation

Observation is intentionally store-first:

- `observe()` on resource fetches emits cached local data first.
- `.once` refreshes one endpoint request, emits the refreshed local result, and completes.
- `.live` stays subscribed to the underlying local query and emits when matching tables change.
- SQLite observation coalesces rapid invalidations per observer instead of spawning a refetch task for every write.

This keeps Koma cross-platform. Apple UI can consume the `AsyncStream` from SwiftUI/TCA, Android Swift can bridge it into coroutine or platform-specific stream adapters, and the core does not depend on Combine, Observation, Android coroutines, or an Apple-only runtime.

## JSON

Koma can use an optimized JSON path for simple REST responses and request bodies that map directly to records. This path is intentionally narrow:

- It supports flat record fields backed by stored columns.
- It supports `String`, signed integer types, `Bool`, `Float`, `Double`, and default `Date` numeric encoding.
- It supports arrays, objects, nulls, unknown fields, nested unknown values, escaped Unicode strings, and non-finite-number validation.
- It does not replace `JSONDecoder`, custom `CodingKeys`, custom decoder strategies, nested models, enums, `Data`, polymorphic payloads, or envelope/adapters.

When the JSON path cannot decode a response, Koma falls back to the configured `JSONDecoder`. Request body encoding errors are reported before the transport sends a request.

You can disable the optimization with:

```swift
let koma = KomaClient(
    baseURL: apiBaseURL,
    store: store,
    transport: transport,
    jsonOptimization: .disabled
)
```

This keeps the public API stable while letting Koma optimize the common typed-record route internally.
