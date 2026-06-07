# Android Swift Setup

Koma exports its macro declarations from the primary module, while the macro implementation remains host-built.

Use macros while building the shared package on the host. Android runtime code should depend on macro-expanded Swift interfaces and the runtime products it uses:

- `Koma`
- `KomaSQLite`
- `KomaHTTP` when REST transport is needed
- `KomaTesting` for test utilities

The bundled SQLite target keeps SQLite behavior predictable across iOS and Android Swift.

When integrating into an app, expose app-specific clients over the Android bridge rather than exposing Koma types directly. This keeps platform UI code insulated from storage details.

Android owns the app sandbox path, so pass an explicit database path from Kotlin into your shared Swift runtime:

```kotlin
class MyApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        val databaseFile = getDatabasePath("koma.sqlite")
        databaseFile.parentFile?.mkdirs()

        sharedRuntime = SharedRuntime(
            baseURL = BuildConfig.API_BASE_URL,
            databasePath = databaseFile.absolutePath,
        )
    }
}
```

Then create Koma from Swift with the cross-platform path API:

```swift
let koma = try await KomaClient.sqlite(
    database: .path(databasePath),
    schema: KomaSchema(modules: [ProjectSchema.self]),
    baseURL: baseURL,
    plugins: [
        KomaBearerAuthPlugin { try await tokenProvider.token() },
        KomaRetryPlugin(maxAttempts: 2)
    ]
)
```

Benchmark Android runtime behavior with:

```sh
scripts/benchmark-android.sh .benchmark-results/android-device
```

This runs the Android-specific benchmark target against Koma, raw SQLite, GRDB, and SQLite.swift where the Android Swift SDK and device support those peers.

Background refresh should be scheduled by the host app:

- iOS: `BGTaskScheduler`
- Android: `WorkManager`

Those jobs can call Koma refresh APIs. Backend-dependent sync, cursors, conflicts, and outbox writes are separate contracts and are not part of the offline read-first runtime.
