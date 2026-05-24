# Android Benchmarks

Android benchmarks are separate from host benchmarks because the fair peer set is different.

Core Data and SwiftData are Apple-only and must not be quoted as Android competitors. Android runs should compare Koma with Android-compatible Swift SQLite libraries and raw SQLite.

## Peer Set

The first Android suite measures:

| Provider | Why included |
| --- | --- |
| Koma SQLite | The public ORM/storage API Android apps will use. |
| Raw SQLite | Lower-bound baseline through Koma's bundled SQLite C target. |
| GRDB | Mature Swift SQLite library with Android compatibility on Swift Package Index. |
| SQLite.swift | Popular type-safe SQLite wrapper with Android compatibility on Swift Package Index. |

SQLiteData also reports Android compatibility on Swift Package Index, but it has a different observation-first API shape. Add it as a focused follow-up benchmark so the comparison is fair rather than rushed.

## What Android Measures

The Android target intentionally starts with portable storage workloads:

- open database and ensure schema
- batch upsert 1k records
- filtered ordered fetch from 10k records with limit 100
- inner join filter from 10k projects and related characters
- left join missing-related-rows query

Right joins are tracked in host Koma/raw benchmarks. Android peer runs focus on inner and left joins because they are the common denominator across SQLite builds on Android devices.

## Running

Use a real Android device for publishable numbers:

```sh
scripts/benchmark-android.sh .benchmark-results/android-pixel
```

Use build-only mode to verify the cross-compile setup without a connected device:

```sh
scripts/benchmark-android.sh .benchmark-results/android-build-only --build-only
```

The script uses the first installed Android Swift SDK by default. Override it when needed:

```sh
TOOLCHAINS=swift \
ANDROID_SWIFT_SDK=swift-6.3-RELEASE_android \
ANDROID_SWIFT_TRIPLE=aarch64-unknown-linux-android35 \
scripts/benchmark-android.sh .benchmark-results/android-pixel
```

For x86 emulator runs:

```sh
ANDROID_SWIFT_TRIPLE=x86_64-unknown-linux-android35 \
scripts/benchmark-android.sh .benchmark-results/android-emulator
```

The Android targets use a small built-in runner instead of `swift-benchmark`. This keeps Android runs free from host-only benchmark support dependencies and makes the executables easy to push through `adb`.

There are two executables:

- `KomaAndroidBenchmarks`: Koma, raw SQLite, and GRDB.
- `KomaAndroidSQLiteSwiftBenchmarks`: SQLite.swift in its own process, because SQLite.swift's portable CSQLite build and Koma's bundled SQLite both define SQLite C symbols.

The script builds both executables, pushes them and adjacent Swift runtime libraries to `/data/local/tmp/koma-benchmarks`, runs them through `adb shell`, and writes:

- `metadata.json`
- `results.txt`
- `summary.md`

The runner prints a Markdown table for humans and `RESULT ... p50_ns=...` lines for scripts.

## Requirements

- Matching Swift 6.3 toolchain and Android Swift SDK.
- Android platform tools with `adb` on `PATH`.
- A connected device or running emulator for full runs.

GRDB and SQLite.swift normally look for a SQLite C module. The Android runner passes Koma's bundled SQLite headers during cross-compilation so peer benchmarks use the same SQLite surface as Koma where possible.

If the build reports a missing `Foundation`, `Dispatch`, or `Swift` module for the selected Android triple, the active Swift toolchain and installed Android Swift SDK do not match. Select the release toolchain with `TOOLCHAINS=swift` or reinstall the Android Swift SDK that matches your local compiler.

## Publishing

Keep Android numbers separate from host macOS numbers:

- Use physical device results for README/release claims.
- Label emulator results as smoke/regression data only.
- Record device model, Android version, ABI, Swift SDK, Koma revision, and benchmark command.
- Avoid comparing Android Koma numbers against Core Data or SwiftData.
