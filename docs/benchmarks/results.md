# Official Benchmark Results

Koma publishes small p50 snapshots in the README and keeps fuller benchmark context here. Release notes should attach the raw `.benchmark-results` directory used for any quoted numbers.

| Koma Version | Environment | Swift | Artifact | Notes |
| --- | --- | --- | --- | --- |
| Open-source prep | Darwin 25.4.0 arm64, SwiftPM benchmark runner | Swift 6.3 release | `.benchmark-results/koma-open-source-apple-20260524` | Apple-platform baseline for the iOS-side runtime, not an on-device iOS claim. Host GRDB storage comparison was disabled for this run because this Swift 6.3 toolchain crashed while compiling the GRDB benchmark target. |
| Open-source prep | Google sdk_gphone16k_arm64 emulator, Android 17 SDK 37 | Swift 6.3 release Android SDK | `.benchmark-results/koma-open-source-android-emulator-20260524` | Android smoke baseline with Koma, raw SQLite, GRDB, and SQLite.swift. |

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
