import Koma

actor BenchmarkNoopStore: KomaStore {
    func ensureSchema(for record: (some KomaEntityRecord).Type) async throws {}

    func upsert(_ records: [some KomaEntityRecord]) async throws {}

    func fetch<Record: KomaEntityRecord>(_ request: KomaQueryRequest<Record>) async throws -> [Record] {
        []
    }

    func count(_ request: KomaQueryRequest<some KomaEntityRecord>) async throws -> Int {
        0
    }

    func delete(_ request: KomaDeleteRequest<some KomaEntityRecord>) async throws -> Int {
        0
    }

    func update(_ request: KomaUpdateRequest<some KomaEntityRecord>) async throws -> Int {
        0
    }

    func transaction<Value: Sendable>(_ body: @Sendable (any KomaStore) async throws -> Value) async throws -> Value {
        try await body(self)
    }
}
