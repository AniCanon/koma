import Koma

actor CountingStore: KomaStore {
    private let base: any KomaStore
    private var fetchCounts: [String: Int] = [:]

    init(base: any KomaStore) {
        self.base = base
    }

    func ensureSchema(for record: (some KomaEntityRecord).Type) async throws {
        try await base.ensureSchema(for: record)
    }

    func upsert(_ records: [some KomaEntityRecord]) async throws {
        try await base.upsert(records)
    }

    func fetch<Record: KomaEntityRecord>(_ request: KomaQueryRequest<Record>) async throws -> [Record] {
        fetchCounts[Record.komaTableName, default: 0] += 1
        return try await base.fetch(request)
    }

    func count(_ request: KomaQueryRequest<some KomaEntityRecord>) async throws -> Int {
        try await base.count(request)
    }

    func delete(_ request: KomaDeleteRequest<some KomaEntityRecord>) async throws -> Int {
        try await base.delete(request)
    }

    func update(_ request: KomaUpdateRequest<some KomaEntityRecord>) async throws -> Int {
        try await base.update(request)
    }

    func transaction<Value: Sendable>(_ body: @Sendable (any KomaStore) async throws -> Value) async throws -> Value {
        try await base.transaction(body)
    }

    func fetchCount(for table: String) -> Int {
        fetchCounts[table, default: 0]
    }
}
