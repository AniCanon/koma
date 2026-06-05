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
- Git dirty: false

Lower is better.

### Storage and Local Resource

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `koma.sqlite.open.ensureSchema` | 0.834 ms | 1.005 ms | 1141 |
| `grdb.sqlite.open.ensureSchema` | 0.360 ms | 0.466 ms | 2571 |
| `coredata.sqlite.open.ensureSchema` | 1.258 ms | 1.508 ms | 760 |
| `koma.sqlite.batchUpsert.1k` | 1.589 ms | 1.778 ms | 610 |
| `koma.sqlite.steadyUpsert.1k` | 1.671 ms | 1.871 ms | 579 |
| `koma.sqlite.observedUpsert.1k.limit100` | 1.765 ms | 2.214 ms | 531 |
| `koma.sqlite.fusedJSONUpsert.1k` | 1.737 ms | 1.875 ms | 562 |
| `koma.sqlite.fusedJSONSteadyUpsert.1k` | 1.747 ms | 1.924 ms | 555 |
| `rawsqlite.batchUpsert.1k` | 1.834 ms | 2.078 ms | 527 |
| `grdb.sqlite.batchUpsert.1k` | 7.737 ms | 8.462 ms | 125 |
| `coredata.sqlite.batchInsert.1k` | 7.655 ms | 9.462 ms | 126 |
| `koma.sqlite.filteredOrderedFetch.10k.limit100` | 0.289 ms | 0.304 ms | 3325 |
| `rawsqlite.filteredOrderedFetch.10k.limit100` | 0.283 ms | 0.312 ms | 3285 |
| `grdb.sqlite.filteredOrderedFetch.10k.limit100` | 0.355 ms | 0.574 ms | 2289 |
| `coredata.sqlite.filteredOrderedFetch.10k.limit100` | 0.535 ms | 0.567 ms | 1778 |
| `koma.sqlite.innerJoinFilter.10k.limit100` | 4.874 ms | 5.259 ms | 200 |
| `rawsqlite.innerJoinFilter.10k.limit100` | 4.813 ms | 5.091 ms | 204 |
| `koma.sqlite.rightJoinMatched.10k.limit100` | 4.993 ms | 5.206 ms | 199 |
| `rawsqlite.rightJoinMatched.10k.limit100` | 5.009 ms | 5.951 ms | 192 |
| `koma.sqlite.leftJoinMissing.10k.limit100` | 7.684 ms | 8.561 ms | 127 |
| `rawsqlite.leftJoinMissing.10k.limit100` | 7.766 ms | 8.086 ms | 129 |
| `koma.resource.localOnly.10k.limit100` | 0.299 ms | 0.315 ms | 3193 |
| `koma.resource.networkFirstFallback.1k` | 2.310 ms | 2.454 ms | 421 |

### Search and Vector

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `koma.sqlite.fullTextSearch.10k` | 0.419 ms | 0.441 ms | 2323 |
| `rawsqlite.fullTextSearch.10k` | 0.471 ms | 0.500 ms | 2032 |
| `grdb.sqlite.fullTextSearch.10k` | 0.455 ms | 0.511 ms | 2056 |
| `koma.sqlite.nearest.10k.dim384` | 7.512 ms | 8.036 ms | 130 |
| `rawsqlite.nearest.10k.dim384` | 7.418 ms | 7.569 ms | 134 |
| `grdb.sqlite.nearest.10k.dim384` | 9.454 ms | 10.027 ms | 104 |
| `koma.sqlite.nearestQuantized.10k.dim384` | 2.458 ms | 3.023 ms | 384 |
| `rawsqlite.nearestQuantized.10k.dim384` | 2.937 ms | 3.723 ms | 319 |
| `koma.sqlite.hybridSearch.10k.dim384` | 8.364 ms | 8.970 ms | 118 |
| `rawsqlite.hybridSearch.10k.dim384` | 8.118 ms | 8.303 ms | 123 |
| `grdb.sqlite.hybridSearch.10k.dim384` | 11.092 ms | 12.100 ms | 89 |
| `koma.sqlite.hybridSearchQuantized.10k.dim384` | 3.574 ms | 3.740 ms | 279 |
| `rawsqlite.hybridSearchQuantized.10k.dim384` | 3.760 ms | 3.961 ms | 263 |
| `koma.vector.cosineScan.10k.dim384` | 2.019 ms | 2.335 ms | 479 |
| `koma.vector.encode.1k.dim384` | 0.083 ms | 0.088 ms | 10000 |
| `koma.vector.decode.1k.dim384` | 0.063 ms | 0.068 ms | 10000 |
| `koma.fusion.rrf.2x1k` | 4.497 ms | 4.858 ms | 218 |

### JSON Codecs

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `network.koma.json.records.decode.10` | 0.002 ms | 0.002 ms | 10000 |
| `network.foundation.jsondecoder.decode.10` | 0.015 ms | 0.015 ms | 10000 |
| `network.yyjson.decoder.decode.10` | 0.006 ms | 0.006 ms | 10000 |
| `network.koma.json.records.decode.1k` | 0.184 ms | 0.195 ms | 5372 |
| `network.foundation.jsondecoder.decode.1k` | 1.328 ms | 1.376 ms | 752 |
| `network.yyjson.decoder.decode.1k` | 0.525 ms | 0.553 ms | 1875 |
| `network.koma.json.records.decode.10k` | 1.905 ms | 1.956 ms | 526 |
| `network.foundation.jsondecoder.decode.10k` | 13.427 ms | 13.648 ms | 74 |
| `network.yyjson.decoder.decode.10k` | 5.472 ms | 5.722 ms | 181 |
| `network.koma.json.records.encode.10` | 0.003 ms | 0.003 ms | 10000 |
| `network.foundation.jsonencoder.encode.10` | 0.012 ms | 0.012 ms | 10000 |
| `network.yyjson.encoder.encode.10` | 0.005 ms | 0.006 ms | 10000 |
| `network.koma.json.records.encode.1k` | 0.331 ms | 0.351 ms | 2970 |
| `network.foundation.jsonencoder.encode.1k` | 1.121 ms | 1.168 ms | 890 |
| `network.yyjson.encoder.encode.1k` | 0.439 ms | 0.468 ms | 2249 |
| `network.koma.json.records.encode.10k` | 3.797 ms | 4.268 ms | 256 |
| `network.foundation.jsonencoder.encode.10k` | 11.330 ms | 11.526 ms | 88 |
| `network.yyjson.encoder.encode.10k` | 4.100 ms | 4.383 ms | 241 |

### Transport and Request Pipeline

| Benchmark | p50 wall clock | p90 wall clock | Samples |
| --- | ---: | ---: | ---: |
| `network.koma.transport.get.data.1k` | 0.077 ms | 0.085 ms | 10000 |
| `network.urlsession.get.data.10` | 0.070 ms | 0.078 ms | 10000 |
| `network.urlsession.get.data.1k` | 0.072 ms | 0.080 ms | 10000 |
| `network.urlsession.get.data.10k` | 0.097 ms | 0.107 ms | 9140 |
| `network.koma.transport.get.jsonrecord.10` | 0.076 ms | 0.086 ms | 10000 |
| `network.koma.transport.get.jsonrecord.1k` | 0.265 ms | 0.282 ms | 3550 |
| `network.koma.transport.get.jsonrecord.10k` | 1.972 ms | 2.029 ms | 504 |
| `network.koma.transport.get.decode.1k` | 1.445 ms | 1.499 ms | 686 |
| `network.koma.transport.get.decode.headers.1k` | 1.449 ms | 1.510 ms | 682 |
| `network.urlsession.get.decode.10` | 0.092 ms | 0.102 ms | 9546 |
| `network.urlsession.get.decode.1k` | 1.500 ms | 1.628 ms | 647 |
| `network.urlsession.get.decode.10k` | 13.984 ms | 14.688 ms | 71 |
| `network.koma.resource.urlsession.networkFirstFallback.1k` | 2.570 ms | 2.730 ms | 385 |
| `network.alamofire.get.decode.1k` | 1.508 ms | 1.561 ms | 656 |
| `network.moya.get.decode.1k` | 1.548 ms | 1.668 ms | 628 |
| `network.apollo.query.networkOnly.1k` | 40.370 ms | 40.960 ms | 25 |

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
