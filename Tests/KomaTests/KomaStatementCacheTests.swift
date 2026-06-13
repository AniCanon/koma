import Foundation
import Koma
import KomaSQLite
import Testing

@KomaEntity(table: "cached_items")
private struct CachedItemRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var rank: Int

    init(id: String, name: String, rank: Int) {
        self.id = id
        self.name = name
        self.rank = rank
    }
}

struct KomaStatementCacheTests {
    private func makeStore() async throws -> SQLiteKomaStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("koma-stmtcache-\(UUID().uuidString).sqlite").path
        return try await SQLiteKomaStore(path: path)
    }

    @Test
    func `repeated identical queries return correct results with fresh bindings`() async throws {
        let store = try await makeStore()
        try await store.upsert([
            CachedItemRecord(id: "a", name: "alpha", rank: 1),
            CachedItemRecord(id: "b", name: "beta", rank: 2),
            CachedItemRecord(id: "c", name: "gamma", rank: 3)
        ])

        // The same SQL shape executes repeatedly; a reused statement must not leak
        // previous bindings or row state.
        for (rank, expected) in [(1, "alpha"), (2, "beta"), (3, "gamma"), (1, "alpha")] {
            let records = try await store.query(CachedItemRecord.self)
                .where { $0.rank == rank }
                .fetch()
            #expect(records.map(\.name) == [expected])
        }

        // Fewer bound parameters than the previous execution of an identical statement
        // must not see stale bindings (clear_bindings on checkin).
        let all = try await store.query(CachedItemRecord.self).fetch()
        #expect(all.count == 3)
    }

    @Test
    func `repeated upserts of the same record type reuse the cached statement`() async throws {
        let store = try await makeStore()
        for index in 0 ..< 50 {
            try await store.upsert([CachedItemRecord(id: "row-\(index)", name: "n\(index)", rank: index)])
        }
        let count = try await store.query(CachedItemRecord.self).count()
        #expect(count == 50)
    }

    @Test
    func `schema change after caching does not break subsequent queries`() async throws {
        let store = try await makeStore()
        try await store.upsert([CachedItemRecord(id: "a", name: "alpha", rank: 1)])
        _ = try await store.query(CachedItemRecord.self).fetch()

        // DDL through the raw path; cached statements re-prepare transparently.
        try await store.rawExecute("CREATE INDEX cached_items_rank ON cached_items(rank)")

        let records = try await store.query(CachedItemRecord.self)
            .where { $0.rank == 1 }
            .fetch()
        #expect(records.map(\.id) == ["a"])
    }
}
