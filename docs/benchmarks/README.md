# Koma Benchmarks

Koma treats benchmark results as versioned release artifacts. A published result must include the Koma git revision or tag, Swift toolchain, OS, CPU/device, SQLite version when available, and the raw benchmark output.

## What We Measure

- `koma.sqlite.open.ensureSchema`: cold SQLite open plus schema creation.
- `koma.sqlite.batchUpsert.1k`: typed Koma batch upsert into the bundled SQLite store.
- `rawsqlite.batchUpsert.1k`: equivalent raw SQLite upsert using the same bundled SQLite C target.
- `grdb.sqlite.batchUpsert.1k`: equivalent GRDB upsert through `DatabaseQueue`.
- `coredata.sqlite.batchInsert.1k`: Core Data `NSBatchInsertRequest` into SQLite.
- `swiftdata.sqlite.insert.1k`: SwiftData model insertion into a file-backed SQLite store.
- `koma.sqlite.filteredOrderedFetch.10k.limit100`: typed filtered, ordered, limited local query.
- `rawsqlite.filteredOrderedFetch.10k.limit100`: equivalent raw SQLite filtered query.
- `koma.sqlite.innerJoinFilter.10k.limit100`: typed inner join against related records, joined-table filter, distinct base rows, ordering, and limit.
- `rawsqlite.innerJoinFilter.10k.limit100`: equivalent raw SQLite inner join query.
- `koma.sqlite.rightJoinMatched.10k.limit100`: typed right join against related records, filtered to matched base rows, distinct base rows, ordering, and limit.
- `rawsqlite.rightJoinMatched.10k.limit100`: equivalent raw SQLite right join query.
- `koma.sqlite.leftJoinMissing.10k.limit100`: typed left join with joined-table null predicate to find base rows without related records.
- `rawsqlite.leftJoinMissing.10k.limit100`: equivalent raw SQLite left join missing-row query.
- `grdb.sqlite.filteredOrderedFetch.10k.limit100`: equivalent GRDB filtered query.
- `coredata.sqlite.filteredOrderedFetch.10k.limit100`: equivalent Core Data filtered fetch.
- `swiftdata.sqlite.filteredOrderedFetch.10k.limit100`: equivalent SwiftData filtered fetch.
- `koma.resource.networkFirstFallback.1k`: fake REST response, JSON decode, record mapping, SQLite persist, local query, and record-to-remote mapping.
- `koma.resource.localOnly.10k.limit100`: resource API local read path over a prewarmed store.
- `koma.sqlite.fullTextSearch.10k`: FTS5 external-content keyword search over a 10k memory corpus.
- `koma.sqlite.nearest.10k.dim384`: exact cosine nearest-neighbor search over 10k stored 384-dim `Float64` embeddings.
- `koma.sqlite.nearestQuantized.10k.dim384`: int8 sidecar pre-filter plus exact rerank over the same corpus.
- `koma.sqlite.hybridSearch.10k.dim384`: reciprocal-rank fusion over FTS5 keyword recall and exact vector recall.
- `koma.sqlite.hybridSearchQuantized.10k.dim384`: reciprocal-rank fusion over FTS5 keyword recall and quantized vector recall.
- `rawsqlite.fullTextSearch.10k`, `rawsqlite.nearest.10k.dim384`, `rawsqlite.nearestQuantized.10k.dim384`, `rawsqlite.hybridSearch.10k.dim384`, and `rawsqlite.hybridSearchQuantized.10k.dim384`: hand-written SQLite baselines for the same search workloads.
- `grdb.sqlite.fullTextSearch.10k`, `grdb.sqlite.nearest.10k.dim384`, and `grdb.sqlite.hybridSearch.10k.dim384`: GRDB peer baselines for the same search workloads.
- `koma.vector.cosineScan.10k.dim384`, `koma.vector.encode.1k.dim384`, `koma.vector.decode.1k.dim384`, and `koma.fusion.rrf.2x1k`: in-memory vector and ranking-fusion primitives used to interpret the store-level search numbers.

The raw SQLite benchmarks are the primary baseline because they are portable across iOS, Android Swift, macOS, and Linux. They should be read as the lower-bound target Koma tries to stay close to, not as a baseline Koma must beat in every case. GRDB is the mature Swift SQLite peer baseline. SwiftData and Core Data are Apple-only comparison suites, so they should not be presented as Android peers. Core Data uses its optimized batch insert API; SwiftData currently uses model insertion because it does not expose an equivalent public batch insert API.

## Running Locally

```sh
scripts/benchmark.sh
```

Run a focused benchmark while iterating:

```sh
scripts/benchmark.sh --filter '.*koma.sqlite.batchUpsert.*'
```

Create a publishable run bundle:

```sh
scripts/benchmark-official.sh .benchmark-results/local-koma
```

The official script writes:

- `metadata.json`: revision, tag, Swift toolchain, platform, and command.
- `results.txt`: raw benchmark runner output.
- `summary.md`: a human-readable run summary.

The scripts default `BENCHMARK_DISABLE_JEMALLOC=true` so contributors do not need a system `jemalloc` install. Set `BENCHMARK_DISABLE_JEMALLOC=false` and install `jemalloc` when you want allocator-specific metrics on a host machine.

The benchmark targets are opt-in through `KOMA_ENABLE_BENCHMARKS=1`, which the scripts set for you. This keeps ordinary `swift test` runs focused on library/test targets and prevents app consumers from resolving benchmark-only dependencies such as Alamofire, Moya, Apollo, GRDB, SQLite.swift, and `swift-benchmark`.

## Running On Android

Android benchmarks use a separate target and peer set:

```sh
scripts/benchmark-android.sh .benchmark-results/android-pixel
```

Use build-only mode when no device is connected:

```sh
scripts/benchmark-android.sh .benchmark-results/android-build-only --build-only
```

See `docs/benchmarks/android.md` for device setup, peer selection, and publishing rules.

## Publishing Official Results

1. Run benchmarks from a clean working tree.
2. Prefer release builds and stable power/thermal conditions.
3. Commit or attach the run directory to a GitHub release.
4. Add a short row to `docs/benchmarks/results.md` with the published artifact link.
5. Keep host CI numbers and real-device numbers separate.

GitHub-hosted benchmark runs are useful for regression detection. Real mobile device runs are the numbers Koma should quote in release notes and README comparisons.
