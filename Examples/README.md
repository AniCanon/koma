# Koma Examples

These examples are small Swift packages that exercise the public Koma API the way an app would use it. They are intended to be read, copied, and compiled while preparing releases.

## Project Browser

`ProjectBrowser` is the canonical end-to-end sample. It shows:

- App bootstrap with `KomaClient`, `SQLiteKomaStore`, plugins, and a token provider.
- DTOs, normalized records, hydrated models, and relationships.
- Enum resource routes with cache and refresh behavior.
- Repository-style dependency injection and a mockable protocol.
- Querying, eager relationship loading with `.include(...)`, lazy relation fetches, and filtered relation queries.
- Concrete refresh registration for parameterized endpoints such as `projects/{projectId}`.

Run it with:

```sh
cd Examples/ProjectBrowser
swift run ProjectBrowser
swift test
```

From the repository root you can validate every example package with:

```sh
scripts/examples.sh
```
