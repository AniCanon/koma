# Official Benchmark Results

Koma publishes small p50 snapshots in the README and keeps fuller benchmark context here. Release notes should attach the raw `.benchmark-results` directory used for any quoted numbers.

| Koma Version | Environment | Swift | Artifact | Notes |
| --- | --- | --- | --- | --- |
| SQLite raw SQL branch validation | Darwin 25.5.0 arm64, SwiftPM benchmark runner | Swift 6.3 release | `.benchmark-results/feat-sqlite-raw-sql-clean-20260605` | Clean-branch validation for raw SQL, FTS5, exact vector search, quantized vector search, hybrid search, storage, JSON, and request-pipeline benchmarks. |
| Live observation branch | Darwin 25.4.0 arm64, SwiftPM benchmark runner | Swift 6.3 release | `.benchmark-results/live-observation-final-20260525` | Final host pass for live observation, fused JSON-to-SQLite binding, generated key dispatch, and projection fast paths. Host GRDB was disabled for this run because this Swift 6.3 toolchain still fails the GRDB benchmark target in release mode. |
| Open-source prep | Darwin 25.4.0 arm64, SwiftPM benchmark runner | Swift 6.3 release | `.benchmark-results/koma-open-source-apple-20260524` | Apple-platform baseline for the iOS-side runtime, not an on-device iOS claim. Host GRDB storage comparison was disabled for this run because this Swift 6.3 toolchain crashed while compiling the GRDB benchmark target. |
| Open-source prep | Google sdk_gphone16k_arm64 emulator, Android 17 SDK 37 | Swift 6.3 release Android SDK | `.benchmark-results/koma-open-source-android-emulator-20260524` | Android smoke baseline with Koma, raw SQLite, GRDB, and SQLite.swift. |

## SQLite Raw SQL Branch Validation

Captured June 5, 2026 from the `feat/sqlite-raw-sql` working tree after adding raw SQL, FTS5, exact vector search, trigger-maintained quantized vector indexes, and hybrid search.

- Command: `BENCHMARK_DISABLE_JEMALLOC=true scripts/benchmark-official.sh .benchmark-results/feat-sqlite-raw-sql-clean-20260605 --metric wallClock --no-progress --time-units microseconds`
- Platform: Darwin 25.5.0 arm64
- Swift: Apple Swift 6.3
- Artifact: `.benchmark-results/feat-sqlite-raw-sql-clean-20260605`
- Git revision: `969a9b9133a665f883f48453efeb8e27ce4778a7`
- Git dirty: false

Lower is better.

### Storage and Local Resource

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `koma.sqlite.open.ensureSchema` | 0.804 ms | 1.013 ms | 1169 |
| `grdb.sqlite.open.ensureSchema` | 0.362 ms | 0.441 ms | 2573 |
| `coredata.sqlite.open.ensureSchema` | 1.274 ms | 1.415 ms | 772 |
| `koma.sqlite.batchUpsert.1k` | 1.577 ms | 1.672 ms | 624 |
| `koma.sqlite.steadyUpsert.1k` | 1.572 ms | 1.690 ms | 622 |
| `koma.sqlite.observedUpsert.1k.limit100` | 1.608 ms | 1.731 ms | 612 |
| `koma.sqlite.fusedJSONUpsert.1k` | 1.694 ms | 1.786 ms | 579 |
| `koma.sqlite.fusedJSONSteadyUpsert.1k` | 1.683 ms | 1.780 ms | 583 |
| `rawsqlite.batchUpsert.1k` | 1.787 ms | 1.881 ms | 555 |
| `grdb.sqlite.batchUpsert.1k` | 7.836 ms | 8.065 ms | 128 |
| `coredata.sqlite.batchInsert.1k` | 7.062 ms | 7.303 ms | 140 |
| `koma.sqlite.filteredOrderedFetch.10k.limit100` | 0.289 ms | 0.307 ms | 3317 |
| `rawsqlite.filteredOrderedFetch.10k.limit100` | 0.277 ms | 0.295 ms | 3452 |
| `grdb.sqlite.filteredOrderedFetch.10k.limit100` | 0.337 ms | 0.357 ms | 2860 |
| `coredata.sqlite.filteredOrderedFetch.10k.limit100` | 0.524 ms | 0.556 ms | 1845 |
| `koma.sqlite.innerJoinFilter.10k.limit100` | 4.805 ms | 5.181 ms | 206 |
| `rawsqlite.innerJoinFilter.10k.limit100` | 4.641 ms | 4.964 ms | 212 |
| `koma.sqlite.rightJoinMatched.10k.limit100` | 4.706 ms | 4.829 ms | 212 |
| `rawsqlite.rightJoinMatched.10k.limit100` | 4.887 ms | 5.333 ms | 202 |
| `koma.sqlite.leftJoinMissing.10k.limit100` | 7.569 ms | 7.684 ms | 132 |
| `rawsqlite.leftJoinMissing.10k.limit100` | 7.328 ms | 7.471 ms | 137 |
| `koma.resource.localOnly.10k.limit100` | 0.298 ms | 0.315 ms | 3218 |
| `koma.resource.networkFirstFallback.1k` | 2.286 ms | 2.503 ms | 425 |

### Search and Vector

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `koma.sqlite.fullTextSearch.10k` | 0.413 ms | 0.435 ms | 2353 |
| `rawsqlite.fullTextSearch.10k` | 0.462 ms | 0.489 ms | 2096 |
| `grdb.sqlite.fullTextSearch.10k` | 0.437 ms | 0.462 ms | 2222 |
| `koma.sqlite.nearest.10k.dim384` | 7.221 ms | 7.500 ms | 137 |
| `rawsqlite.nearest.10k.dim384` | 7.127 ms | 7.274 ms | 140 |
| `grdb.sqlite.nearest.10k.dim384` | 9.626 ms | 9.765 ms | 104 |
| `koma.sqlite.nearestQuantized.10k.dim384` | 2.400 ms | 2.521 ms | 414 |
| `rawsqlite.nearestQuantized.10k.dim384` | 2.454 ms | 2.531 ms | 403 |
| `koma.sqlite.hybridSearch.10k.dim384` | 8.495 ms | 8.626 ms | 118 |
| `rawsqlite.hybridSearch.10k.dim384` | 8.454 ms | 8.954 ms | 117 |
| `grdb.sqlite.hybridSearch.10k.dim384` | 10.338 ms | 10.543 ms | 97 |
| `koma.sqlite.hybridSearchQuantized.10k.dim384` | 3.633 ms | 3.805 ms | 274 |
| `rawsqlite.hybridSearchQuantized.10k.dim384` | 3.451 ms | 3.705 ms | 284 |
| `koma.vector.cosineScan.10k.dim384` | 1.962 ms | 2.008 ms | 509 |
| `koma.vector.encode.1k.dim384` | 0.083 ms | 0.089 ms | 10000 |
| `koma.vector.decode.1k.dim384` | 0.062 ms | 0.067 ms | 10000 |
| `koma.fusion.rrf.2x1k` | 4.518 ms | 4.600 ms | 221 |

### JSON Codecs

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `network.koma.json.records.decode.10` | 0.002 ms | 0.002 ms | 10000 |
| `network.foundation.jsondecoder.decode.10` | 0.015 ms | 0.016 ms | 10000 |
| `network.yyjson.decoder.decode.10` | 0.006 ms | 0.006 ms | 10000 |
| `network.koma.json.records.decode.1k` | 0.181 ms | 0.192 ms | 5465 |
| `network.foundation.jsondecoder.decode.1k` | 1.369 ms | 1.439 ms | 724 |
| `network.yyjson.decoder.decode.1k` | 0.518 ms | 0.546 ms | 1918 |
| `network.koma.json.records.decode.10k` | 1.805 ms | 1.853 ms | 554 |
| `network.foundation.jsondecoder.decode.10k` | 13.926 ms | 14.680 ms | 72 |
| `network.yyjson.decoder.decode.10k` | 5.239 ms | 5.341 ms | 191 |
| `network.koma.json.records.encode.10` | 0.004 ms | 0.004 ms | 10000 |
| `network.foundation.jsonencoder.encode.10` | 0.012 ms | 0.013 ms | 10000 |
| `network.yyjson.encoder.encode.10` | 0.004 ms | 0.005 ms | 10000 |
| `network.koma.json.records.encode.1k` | 0.324 ms | 0.344 ms | 3055 |
| `network.foundation.jsonencoder.encode.1k` | 1.116 ms | 1.165 ms | 895 |
| `network.yyjson.encoder.encode.1k` | 0.408 ms | 0.431 ms | 2431 |
| `network.koma.json.records.encode.10k` | 3.377 ms | 3.551 ms | 294 |
| `network.foundation.jsonencoder.encode.10k` | 11.158 ms | 11.362 ms | 90 |
| `network.yyjson.encoder.encode.10k` | 4.063 ms | 4.168 ms | 246 |

### Transport and Request Pipeline

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `network.koma.transport.get.data.1k` | 0.077 ms | 0.086 ms | 10000 |
| `network.urlsession.get.data.10` | 0.071 ms | 0.078 ms | 10000 |
| `network.urlsession.get.data.1k` | 0.072 ms | 0.082 ms | 10000 |
| `network.urlsession.get.data.10k` | 0.097 ms | 0.106 ms | 9174 |
| `network.koma.transport.get.jsonrecord.10` | 0.077 ms | 0.088 ms | 10000 |
| `network.koma.transport.get.jsonrecord.1k` | 0.267 ms | 0.288 ms | 3510 |
| `network.koma.transport.get.jsonrecord.10k` | 1.930 ms | 1.998 ms | 515 |
| `network.koma.transport.get.decode.1k` | 1.415 ms | 1.467 ms | 700 |
| `network.koma.transport.get.decode.headers.1k` | 1.444 ms | 1.629 ms | 659 |
| `network.urlsession.get.decode.10` | 0.095 ms | 0.123 ms | 8441 |
| `network.urlsession.get.decode.1k` | 1.408 ms | 1.479 ms | 693 |
| `network.urlsession.get.decode.10k` | 13.664 ms | 13.795 ms | 74 |
| `network.koma.resource.urlsession.networkFirstFallback.1k` | 2.462 ms | 2.648 ms | 402 |
| `network.alamofire.get.decode.1k` | 1.500 ms | 1.561 ms | 661 |
| `network.moya.get.decode.1k` | 1.517 ms | 1.571 ms | 654 |
| `network.apollo.query.networkOnly.1k` | 40.206 ms | 40.763 ms | 25 |

## Live Observation Branch

Captured May 25, 2026 from `feature/live-observation`.

- Command: `KOMA_DISABLE_GRDB_BENCHMARKS=1 scripts/benchmark-official.sh .benchmark-results/live-observation-final-20260525`
- Platform: Darwin 25.4.0 arm64
- Swift: Apple Swift 6.3
- Artifact: `.benchmark-results/live-observation-final-20260525`

### Storage

| Benchmark | p50 wall clock | p50 instructions |
| --- | ---: | ---: |
| `koma.sqlite.batchUpsert.1k` | 1.678 ms | 24M |
| `rawsqlite.batchUpsert.1k` | 1.953 ms | 29M |
| `koma.sqlite.observedUpsert.1k.limit100` | 2.652 ms | 26M |
| `koma.sqlite.fusedJSONUpsert.1k` | 2.099 ms | 30M |
| `koma.sqlite.filteredOrderedFetch.10k.limit100` | 8.360 ms | 182M |
| `rawsqlite.filteredOrderedFetch.10k.limit100` | 10.000 ms | 226M |
| `coredata.sqlite.batchInsert.1k` | 16.000 ms | 116M |
| `coredata.sqlite.filteredOrderedFetch.10k.limit100` | 102.000 ms | 1000M |
| `swiftdata.sqlite.insert.1k` | 128.000 ms | 999M |
| `swiftdata.sqlite.filteredOrderedFetch.10k.limit100` | 854.000 ms | 9924M |

### JSON and Resource Pipeline

| Benchmark | p50 wall clock | p50 instructions |
| --- | ---: | ---: |
| `network.koma.json.records.decode.1k` | 0.409 ms | 6.3M |
| `network.foundation.jsondecoder.decode.1k` | 2.839 ms | 39M |
| `network.yyjson.decoder.decode.1k` | 0.874 ms | 14M |
| `network.koma.json.records.encode.1k` | 0.594 ms | 10.0M |
| `network.foundation.jsonencoder.encode.1k` | 2.288 ms | 29M |
| `network.yyjson.encoder.encode.1k` | 0.391 ms | 12M |
| `koma.resource.networkFirstFallback.1k` | 2.320 ms | 44M |
| `network.koma.resource.urlsession.networkFirstFallback.1k` | 4.334 ms | 46M |
| `network.koma.transport.get.decode.1k` | 2.621 ms | 41M |
| `network.alamofire.get.decode.1k` | 3.400 ms | 41M |
| `network.moya.get.decode.1k` | 3.125 ms | 41M |
| `network.apollo.query.networkOnly.1k` | 85.000 ms | 1016M |

## Open-Source Prep Baseline

Captured May 24, 2026 from the open-source preparation working tree. Lower is better.

### Apple/Darwin Storage

| Operation | Koma | Raw SQLite | Core Data | SwiftData |
| --- | ---: | ---: | ---: | ---: |
| Open + ensure schema | 0.815 ms | n/a | 1.662 ms | 1.622 ms |
| Upsert or insert 1k records | 2.055 ms | 1.938 ms | 8.282 ms | 53.000 ms |
| Filtered fetch 10k, limit 100 | 12.000 ms | 11.000 ms | 54.000 ms | 550.000 ms |
| Inner join filter 10k, limit 100 | 33.000 ms | 30.000 ms | n/a | n/a |

### Android Emulator Storage

| Operation | Koma | Raw SQLite | GRDB | SQLite.swift |
| --- | ---: | ---: | ---: | ---: |
| Open + ensure schema | 4.432 ms | 4.540 ms | 1.939 ms | 4.800 ms |
| Upsert 1k records | 5.487 ms | 5.904 ms | 12.054 ms | 6.406 ms |
| Filtered fetch 10k, limit 100 | 0.409 ms | 0.383 ms | 0.484 ms | 0.472 ms |
| Inner join filter 10k, limit 100 | 5.023 ms | 4.963 ms | 4.929 ms | 4.835 ms |
| Left join missing 10k, limit 100 | 7.266 ms | 7.208 ms | 7.231 ms | 7.213 ms |

### JSON and Request Pipeline

| Platform | Operation | Koma | Foundation | YYJSON | Other |
| --- | --- | ---: | ---: | ---: | ---: |
| Apple/Darwin | Decode 1k records | 0.283 ms | 1.335 ms | 0.529 ms | n/a |
| Apple/Darwin | Encode 1k records | 0.381 ms | 1.146 ms | 0.415 ms | n/a |
| Apple/Darwin | Mock GET + decode 1k | 0.371 ms | 1.469 ms | n/a | Alamofire 1.555 ms, Moya 1.556 ms, Apollo 41.000 ms |
| Android emulator | Decode 1k records | 0.420 ms | 1.640 ms | 0.949 ms | n/a |
| Android emulator | Encode 1k records | 0.591 ms | 1.378 ms | 0.739 ms | n/a |

## Android Results

Android results must stay separate from host macOS results. Quote physical-device runs for release claims; keep emulator runs for smoke checks and regressions.

## Join API Local Baseline

These numbers were captured from the join API working tree and should be treated as development data, not release claims. This run covers the closure-based `join`, `leftJoin`, and `rightJoin` APIs against equivalent raw SQLite queries.

- Command: `scripts/benchmark-official.sh .benchmark-results/koma-joins-right-local`
- Platform: Darwin 25.4.0 arm64
- Swift: Apple Swift 6.3
- Artifact: `.benchmark-results/koma-joins-right-local`

### Join Queries

| Provider | Inner join filter | Right join matched | Left join missing |
| --- | ---: | ---: | ---: |
| Raw SQLite | 27.00 ms | 27.00 ms | 29.00 ms |
| Koma SQLite | 27.00 ms | 27.00 ms | 30.00 ms |

### Storage Providers

| Provider | Write 1k | Filtered fetch 10k | Open schema |
| --- | ---: | ---: | ---: |
| Raw SQLite | 1.778 ms | 10.00 ms | n/a |
| Koma SQLite | 1.804 ms | 10.00 ms | 0.686 ms |
| GRDB | 7.160 ms | 68.00 ms | 0.317 ms |
| Core Data | 7.209 ms | 46.00 ms | 1.360 ms |
| SwiftData | 47.00 ms | 445.00 ms | 1.390 ms |

### Network Providers

| Provider | Path | Payload | p50 wall clock |
| --- | --- | ---: | ---: |
| Koma | URLSession transport + JSON record path | 1k records | 0.346 ms |
| URLSession | data + `JSONDecoder` | 1k records | 1.336 ms |
| Koma | URLSession transport + `JSONDecoder` | 1k records | 1.326 ms |
| Alamofire | request + `JSONDecoder` | 1k records | 1.386 ms |
| Moya | request + `JSONDecoder` | 1k records | 1.412 ms |
| Koma | Resource `networkFirstFallback` | 1k records | 2.576 ms |
| Apollo | GraphQL network-only query | 1k records | 37.00 ms |

## v1 Parity Local Baseline

These numbers were captured from the v1 parity working tree and should be treated as development data, not release claims.

- Command: `scripts/benchmark-official.sh .benchmark-results/koma-v1-local`
- Platform: Darwin 25.4.0 arm64
- Swift: Apple Swift 6.3
- Artifact: `.benchmark-results/koma-v1-local`

| Benchmark | p50 wall clock |
| --- | ---: |
| `rawsqlite.batchUpsert.1k` | 1.70 ms |
| `koma.sqlite.batchUpsert.1k` | 1.84 ms |
| `coredata.sqlite.batchInsert.1k` | 7.32 ms |
| `grdb.sqlite.batchUpsert.1k` | 7.60 ms |
| `swiftdata.sqlite.insert.1k` | 49.00 ms |
| `rawsqlite.filteredOrderedFetch.10k.limit100` | 10.00 ms |
| `koma.sqlite.filteredOrderedFetch.10k.limit100` | 11.00 ms |
| `coredata.sqlite.filteredOrderedFetch.10k.limit100` | 47.00 ms |
| `grdb.sqlite.filteredOrderedFetch.10k.limit100` | 73.00 ms |
| `swiftdata.sqlite.filteredOrderedFetch.10k.limit100` | 468.00 ms |
| `koma.resource.networkFirstFallback.1k` | 3.65 ms |
| `koma.resource.localOnly.10k.limit100` | 11.00 ms |
| `grdb.sqlite.open.ensureSchema` | 0.30 ms |
| `koma.sqlite.open.ensureSchema` | 0.67 ms |
| `swiftdata.sqlite.open.ensureSchema` | 1.37 ms |
| `coredata.sqlite.open.ensureSchema` | 1.37 ms |

## JSON Development Run

These numbers are local development data from the JSON and direct SQLite binding pass. They are useful for optimization direction, not a release claim.

- Command: `BENCHMARK_DISABLE_JEMALLOC=true scripts/benchmark-official.sh .benchmark-results/koma-json-final`
- Platform: Darwin 25.4.0 arm64
- Swift: Apple Swift 6.3
- Artifact: `.benchmark-results/koma-json-final`

### Network Providers

| Provider | Path | Payload | p50 wall clock |
| --- | --- | ---: | ---: |
| Koma | URLSession transport + JSON | 10 records | 0.077 ms |
| URLSession | data + `JSONDecoder` | 10 records | 0.091 ms |
| Koma | URLSession transport + JSON | 1k records | 0.443 ms |
| URLSession | data + `JSONDecoder` | 1k records | 1.416 ms |
| Moya | request + `JSONDecoder` | 1k records | 1.529 ms |
| Alamofire | request + `JSONDecoder` | 1k records | 1.530 ms |
| Koma | URLSession transport + JSON | 10k records | 3.891 ms |
| URLSession | data + `JSONDecoder` | 10k records | 14.00 ms |
| Apollo | GraphQL network-only query | 1k records | 40.00 ms |

### Storage Providers

| Provider | Write 1k | Filtered fetch 10k | Open schema |
| --- | ---: | ---: | ---: |
| Raw SQLite | 1.772 ms | 10.00 ms | n/a |
| Koma SQLite | 1.855 ms | 11.00 ms | 0.712 ms |
| GRDB | 7.815 ms | 77.00 ms | 0.319 ms |
| Core Data | 7.950 ms | 48.00 ms | 1.437 ms |
| SwiftData | 51.00 ms | 530.00 ms | 1.514 ms |

### Koma Internals

| Koma Path | Payload | p50 wall clock |
| --- | ---: | ---: |
| Koma JSON decode only | 10 records | 0.0045 ms |
| Koma JSON decode only | 1k records | 0.349 ms |
| Koma JSON decode only | 10k records | 3.437 ms |
| Transport data only | 1k records | 0.074 ms |
| Transport + `JSONDecoder` | 1k records | 1.414 ms |
| Transport + JSON | 1k records | 0.443 ms |
| Resource `networkFirstFallback` | 1k records | 2.798 ms |
| Resource URLSession `networkFirstFallback` | 1k records | 3.848 ms |

## Development Baseline

These numbers are local, pre-release, and not official because they were captured from an uncommitted working tree. They are useful as the first optimization baseline after the SQLite fast path, automatic additive migrations, and composable migration packs.

- Command: `scripts/benchmark-official.sh .benchmark-results/20260523-migrations-final`
- Host: `Rauls-MacBook-Pro.local`, 18-core arm64, 64 GB memory, Darwin 25.4.0.
- Artifact: `.benchmark-results/20260523-migrations-final` (ignored locally; attach a copied artifact to a release when publishing official numbers).

| Benchmark | p50 wall clock |
| --- | ---: |
| `rawsqlite.batchUpsert.1k` | 1.97 ms |
| `koma.sqlite.batchUpsert.1k` | 1.99 ms |
| `coredata.sqlite.batchInsert.1k` | 7.70 ms |
| `grdb.sqlite.batchUpsert.1k` | 8.32 ms |
| `swiftdata.sqlite.insert.1k` | 53.00 ms |
| `rawsqlite.filteredOrderedFetch.10k.limit100` | 11.00 ms |
| `koma.sqlite.filteredOrderedFetch.10k.limit100` | 12.00 ms |
| `coredata.sqlite.filteredOrderedFetch.10k.limit100` | 50.00 ms |
| `grdb.sqlite.filteredOrderedFetch.10k.limit100` | 77.00 ms |
| `swiftdata.sqlite.filteredOrderedFetch.10k.limit100` | 499.00 ms |
| `koma.resource.networkFirstFallback.1k` | 3.89 ms |
| `koma.resource.localOnly.10k.limit100` | 12.00 ms |
| `grdb.sqlite.open.ensureSchema` | 0.33 ms |
| `koma.sqlite.open.ensureSchema` | 0.77 ms |
| `swiftdata.sqlite.open.ensureSchema` | 1.55 ms |
| `coredata.sqlite.open.ensureSchema` | 1.70 ms |
