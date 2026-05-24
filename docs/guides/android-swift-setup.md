# Android Swift Setup

Koma separates host-built macros from runtime targets.

Use macros while building the shared package on the host. Android runtime code should depend on macro-expanded Swift interfaces and runtime targets:

- `Koma`
- `KomaSQLite`
- `KomaHTTP` when REST transport is needed
- `KomaTesting` for test utilities

The bundled SQLite target keeps SQLite behavior predictable across iOS and Android Swift.

When integrating into an app, expose app-specific clients over the Android bridge rather than exposing Koma types directly. This keeps platform UI code insulated from storage details.

Background refresh should be scheduled by the host app:

- iOS: `BGTaskScheduler`
- Android: `WorkManager`

Those jobs can call Koma refresh APIs. Backend-dependent sync, cursors, conflicts, and outbox writes are separate contracts and are not part of the offline read-first runtime.
