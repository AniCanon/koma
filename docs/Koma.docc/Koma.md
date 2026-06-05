# Koma

Koma is a small Swift 6.3 SQLite ORM and refresh framework created by AniCanon for offline read-first apps on iOS and Android Swift.

## Overview

Koma stores typed, normalized records in SQLite and composes them with lazy queries, REST resources, adapters, plugins, and model hydration. It does not store opaque REST payload blobs, and it does not try to replace hand-written SQLite everywhere. The goal is typed app ergonomics with performance close to raw SQLite on common local workloads.

Sync engines, outboxes, conflict resolution, and cursor contracts are intentionally deferred until the backend contract exists.

This DocC catalog is intentionally focused on API reference generated from the Swift package. The broader handbook, architecture notes, raw SQL and local search guide, philosophy, and examples live as plain Markdown under `docs/`.
