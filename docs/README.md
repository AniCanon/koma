# Koma Documentation

This folder is the source of truth for Koma's human-readable documentation.

DocC is still used for generated Swift API reference, but the broader handbook lives here as regular Markdown so it can be read on GitHub, reviewed in pull requests, and maintained without treating conceptual docs like generated output.

## Start Here

- [Getting Started](guides/getting-started.md)
- [Storage-Only Mode](guides/storage-only.md)
- [Examples](guides/examples.md)
- [Philosophy](guides/philosophy.md)
- [Android Swift Setup](guides/android-swift-setup.md)

## Modeling Data

- [Entities and Records](guides/entities-and-records.md)
- [Relationships](guides/relationships.md)
- [Adapters](guides/adapters.md)

## Reading and Writing

- [Querying](guides/querying.md)
- [Storage-Only Mode](guides/storage-only.md)
- [REST Resources](guides/rest-resources.md)
- [Scheduled Refresh](guides/scheduled-refresh.md)
- [Migrations](guides/migrations.md)

## Project Quality

- [Architecture](guides/architecture.md)
- [Testing and Dependency Injection](guides/testing-and-dependency-injection.md)
- [Performance and Benchmarks](guides/performance-and-benchmarks.md)
- [Benchmark Methodology](benchmarks/README.md)
- [Benchmark Results](benchmarks/results.md)

## API Reference

The DocC API reference catalog lives at [Koma.docc](Koma.docc/Koma.md). Build and preview it with:

```sh
scripts/docs.sh
scripts/docs-preview.sh
```
