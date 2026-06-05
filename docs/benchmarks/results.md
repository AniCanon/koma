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
- Git revision: `780c8232b946902202d36bf37c11ccbf46ade23f`
- Git dirty: false

Lower is better.

### Storage and Local Resource

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `koma.sqlite.open.ensureSchema` | 0.866 ms | 1.126 ms | 1076 |
| `grdb.sqlite.open.ensureSchema` | 0.344 ms | 0.380 ms | 2793 |
| `coredata.sqlite.open.ensureSchema` | 1.255 ms | 1.385 ms | 782 |
| `koma.sqlite.batchUpsert.1k` | 1.532 ms | 1.712 ms | 618 |
| `koma.sqlite.steadyUpsert.1k` | 1.546 ms | 1.939 ms | 595 |
| `koma.sqlite.observedUpsert.1k.limit100` | 1.707 ms | 2.109 ms | 542 |
| `koma.sqlite.fusedJSONUpsert.1k` | 1.693 ms | 1.804 ms | 565 |
| `koma.sqlite.fusedJSONSteadyUpsert.1k` | 1.618 ms | 1.729 ms | 597 |
| `rawsqlite.batchUpsert.1k` | 1.789 ms | 2.044 ms | 538 |
| `grdb.sqlite.batchUpsert.1k` | 7.938 ms | 8.106 ms | 126 |
| `coredata.sqlite.batchInsert.1k` | 6.996 ms | 7.225 ms | 141 |
| `koma.sqlite.filteredOrderedFetch.10k.limit100` | 0.284 ms | 0.294 ms | 3390 |
| `rawsqlite.filteredOrderedFetch.10k.limit100` | 0.283 ms | 0.305 ms | 3314 |
| `grdb.sqlite.filteredOrderedFetch.10k.limit100` | 0.344 ms | 0.364 ms | 2798 |
| `coredata.sqlite.filteredOrderedFetch.10k.limit100` | 0.537 ms | 0.562 ms | 1806 |
| `koma.sqlite.innerJoinFilter.10k.limit100` | 4.461 ms | 4.682 ms | 220 |
| `rawsqlite.innerJoinFilter.10k.limit100` | 4.641 ms | 5.038 ms | 212 |
| `koma.sqlite.rightJoinMatched.10k.limit100` | 5.030 ms | 5.530 ms | 194 |
| `rawsqlite.rightJoinMatched.10k.limit100` | 4.530 ms | 4.649 ms | 220 |
| `koma.sqlite.leftJoinMissing.10k.limit100` | 7.053 ms | 7.369 ms | 140 |
| `rawsqlite.leftJoinMissing.10k.limit100` | 8.057 ms | 10.109 ms | 117 |
| `koma.resource.localOnly.10k.limit100` | 0.299 ms | 0.312 ms | 3219 |
| `koma.resource.networkFirstFallback.1k` | 2.210 ms | 2.327 ms | 446 |

### Search and Vector

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `koma.sqlite.fullTextSearch.10k` | 0.414 ms | 0.424 ms | 2365 |
| `rawsqlite.fullTextSearch.10k` | 0.476 ms | 0.545 ms | 1946 |
| `grdb.sqlite.fullTextSearch.10k` | 0.438 ms | 0.458 ms | 2212 |
| `koma.sqlite.nearest.10k.dim384` | 7.389 ms | 7.897 ms | 133 |
| `rawsqlite.nearest.10k.dim384` | 7.729 ms | 8.184 ms | 128 |
| `grdb.sqlite.nearest.10k.dim384` | 8.774 ms | 8.954 ms | 114 |
| `koma.sqlite.nearestQuantized.10k.dim384` | 2.384 ms | 2.714 ms | 404 |
| `rawsqlite.nearestQuantized.10k.dim384` | 2.460 ms | 2.560 ms | 402 |
| `koma.sqlite.hybridSearch.10k.dim384` | 7.950 ms | 8.421 ms | 124 |
| `rawsqlite.hybridSearch.10k.dim384` | 8.634 ms | 9.732 ms | 112 |
| `grdb.sqlite.hybridSearch.10k.dim384` | 9.650 ms | 10.150 ms | 103 |
| `koma.sqlite.hybridSearchQuantized.10k.dim384` | 3.355 ms | 3.791 ms | 285 |
| `rawsqlite.hybridSearchQuantized.10k.dim384` | 3.625 ms | 4.057 ms | 268 |
| `koma.vector.cosineScan.10k.dim384` | 1.944 ms | 1.972 ms | 511 |
| `koma.vector.encode.1k.dim384` | 0.081 ms | 0.085 ms | 10000 |
| `koma.vector.decode.1k.dim384` | 0.062 ms | 0.065 ms | 10000 |
| `koma.fusion.rrf.2x1k` | 4.395 ms | 4.522 ms | 226 |

### JSON Codecs

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `network.koma.json.records.decode.10` | 0.002 ms | 0.002 ms | 10000 |
| `network.foundation.jsondecoder.decode.10` | 0.015 ms | 0.016 ms | 10000 |
| `network.yyjson.decoder.decode.10` | 0.006 ms | 0.006 ms | 10000 |
| `network.koma.json.records.decode.1k` | 0.180 ms | 0.190 ms | 5485 |
| `network.foundation.jsondecoder.decode.1k` | 1.351 ms | 1.419 ms | 735 |
| `network.yyjson.decoder.decode.1k` | 0.530 ms | 0.552 ms | 1879 |
| `network.koma.json.records.decode.10k` | 1.803 ms | 1.885 ms | 552 |
| `network.foundation.jsondecoder.decode.10k` | 13.656 ms | 17.285 ms | 70 |
| `network.yyjson.decoder.decode.10k` | 5.210 ms | 5.349 ms | 192 |
| `network.koma.json.records.encode.10` | 0.003 ms | 0.004 ms | 10000 |
| `network.foundation.jsonencoder.encode.10` | 0.012 ms | 0.012 ms | 10000 |
| `network.yyjson.encoder.encode.10` | 0.005 ms | 0.005 ms | 10000 |
| `network.koma.json.records.encode.1k` | 0.348 ms | 0.368 ms | 2852 |
| `network.foundation.jsonencoder.encode.1k` | 1.115 ms | 1.188 ms | 889 |
| `network.yyjson.encoder.encode.1k` | 0.425 ms | 0.459 ms | 2298 |
| `network.koma.json.records.encode.10k` | 3.451 ms | 3.746 ms | 283 |
| `network.foundation.jsonencoder.encode.10k` | 11.076 ms | 11.952 ms | 90 |
| `network.yyjson.encoder.encode.10k` | 4.123 ms | 4.530 ms | 237 |

### Transport and Request Pipeline

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `network.koma.transport.get.data.1k` | 0.077 ms | 0.091 ms | 10000 |
| `network.urlsession.get.data.10` | 0.070 ms | 0.078 ms | 10000 |
| `network.urlsession.get.data.1k` | 0.072 ms | 0.080 ms | 10000 |
| `network.urlsession.get.data.10k` | 0.098 ms | 0.106 ms | 9083 |
| `network.koma.transport.get.jsonrecord.10` | 0.076 ms | 0.086 ms | 10000 |
| `network.koma.transport.get.jsonrecord.1k` | 0.270 ms | 0.291 ms | 3503 |
| `network.koma.transport.get.jsonrecord.10k` | 1.919 ms | 2.016 ms | 513 |
| `network.koma.transport.get.decode.1k` | 1.502 ms | 1.705 ms | 645 |
| `network.koma.transport.get.decode.headers.1k` | 1.455 ms | 1.553 ms | 674 |
| `network.urlsession.get.decode.10` | 0.092 ms | 0.109 ms | 9062 |
| `network.urlsession.get.decode.1k` | 1.421 ms | 1.462 ms | 695 |
| `network.urlsession.get.decode.10k` | 13.378 ms | 13.697 ms | 75 |
| `network.koma.resource.urlsession.networkFirstFallback.1k` | 2.570 ms | 2.955 ms | 378 |
| `network.alamofire.get.decode.1k` | 1.516 ms | 1.698 ms | 641 |
| `network.moya.get.decode.1k` | 1.529 ms | 1.612 ms | 644 |
| `network.apollo.query.networkOnly.1k` | 39.322 ms | 42.041 ms | 26 |

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
