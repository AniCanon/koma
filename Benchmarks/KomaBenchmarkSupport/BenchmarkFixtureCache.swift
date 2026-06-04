import Foundation

/// Caches expensive, read-only benchmark fixtures (populated databases) so they are built
/// exactly once and reused across every measured iteration of a benchmark.
///
/// ordo re-invokes a benchmark closure on every iteration and measures the whole closure, so
/// creating + populating a database inside the closure makes the reported time the *setup*
/// (e.g. a 10k-row insert), not the operation under test. Fetching the fixture from this cache
/// keeps the per-iteration body down to just the query: the first request builds it, all later
/// requests reuse the same handle. Pair with `benchmark.startMeasurement()` after the cache
/// lookup so neither the build nor the lookup is part of the measured region.
///
/// Cached fixtures intentionally outlive their temporary database files for the lifetime of the
/// benchmark process (no per-iteration teardown) — they must persist to be reused. The OS
/// reclaims the temp files when the process exits.
public actor BenchmarkFixtureCache {
    public static let shared = BenchmarkFixtureCache()

    private var values: [String: any Sendable] = [:]

    public init() {}

    /// Returns the cached fixture for `key`, building and storing it on first request.
    public func value<Value: Sendable>(
        _ key: String,
        make: @Sendable () async throws -> Value
    ) async throws -> Value {
        if let cached = values[key] as? Value {
            return cached
        }
        let created = try await make()
        values[key] = created
        return created
    }
}
