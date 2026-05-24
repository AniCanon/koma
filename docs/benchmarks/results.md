# Official Benchmark Results

No official Koma benchmark result has been published yet.

The first publishable run should be created with:

```sh
scripts/benchmark-official.sh .benchmark-results/koma-<version>-<device>
```

Then attach the run directory to the GitHub release and add a row below.

| Koma Version | Environment | Swift | Artifact | Notes |
| --- | --- | --- | --- | --- |
| Pending | Pending first release run | Pending | Pending | Establish baseline before quoting numbers in README. |

## Android Results

No Android device result has been published yet.

The first Android run should be created with:

```sh
scripts/benchmark-android.sh .benchmark-results/koma-android-<version>-<device>
```

Android results must stay separate from host macOS results. Quote physical-device runs for releases; keep emulator runs for smoke checks and regressions.

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
