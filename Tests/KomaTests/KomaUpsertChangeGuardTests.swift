import Foundation
import Koma
import KomaSQLite
import Testing

@KomaEntity(table: "guarded_items")
private struct GuardedItemRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var rank: Int
    var note: String?

    init(id: String, name: String, rank: Int, note: String? = nil) {
        self.id = id
        self.name = name
        self.rank = rank
        self.note = note
    }
}

@KomaEntity(table: "guarded_keys")
private struct GuardedKeyRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String

    init(id: String) {
        self.id = id
    }
}

struct KomaUpsertChangeGuardTests {
    private func makeStore() async throws -> SQLiteKomaStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("koma-changeguard-\(UUID().uuidString).sqlite").path
        return try await SQLiteKomaStore(path: path)
    }

    @Test
    func `re-upserting identical records does not notify observers`() async throws {
        let store = try await makeStore()
        let records = [
            GuardedItemRecord(id: "a", name: "alpha", rank: 1),
            GuardedItemRecord(id: "b", name: "beta", rank: 2, note: nil)
        ]
        try await store.upsert(records)

        let probe = ObservationProbe<[GuardedItemRecord]>()
        let request = KomaQueryRequest(record: GuardedItemRecord.self)
        let stream = store.observe(request, observing: [])
        let observer = Task {
            for try await emission in stream {
                await probe.append(emission)
            }
        }
        _ = try await withObservationTimeout(.seconds(5)) {
            await probe.waitForCount(1)
        }

        // Byte-identical payload: the change guard keeps every row untouched, so no signal.
        try await store.upsert(records)
        try await Task.sleep(for: .milliseconds(200))
        #expect(await probe.snapshot().count == 1)

        // A real change still notifies.
        try await store.upsert([GuardedItemRecord(id: "a", name: "alpha prime", rank: 1)])
        let emissions = try await withObservationTimeout(.seconds(5)) {
            await probe.waitForCount(2)
        }
        #expect(emissions.count == 2)
        #expect(emissions[1].first(where: { $0.id == "a" })?.name == "alpha prime")
        observer.cancel()
    }

    @Test
    func `identical and changed upserts both leave correct data`() async throws {
        let store = try await makeStore()
        let original = GuardedItemRecord(id: "a", name: "alpha", rank: 1, note: "n")
        try await store.upsert([original])
        try await store.upsert([original])

        var fetched = try await store.query(GuardedItemRecord.self).fetch()
        #expect(fetched == [original])

        let changed = GuardedItemRecord(id: "a", name: "alpha", rank: 2, note: nil)
        try await store.upsert([changed])
        fetched = try await store.query(GuardedItemRecord.self).fetch()
        #expect(fetched == [changed])
    }

    @Test
    func `null transitions are detected as changes`() async throws {
        let store = try await makeStore()
        try await store.upsert([GuardedItemRecord(id: "a", name: "alpha", rank: 1, note: nil)])
        try await store.upsert([GuardedItemRecord(id: "a", name: "alpha", rank: 1, note: "set")])
        let fetched = try await store.query(GuardedItemRecord.self).fetch()
        #expect(fetched.first?.note == "set")
    }

    @Test
    func `key-only records can be re-upserted without error`() async throws {
        let store = try await makeStore()
        try await store.upsert([GuardedKeyRecord(id: "only")])
        try await store.upsert([GuardedKeyRecord(id: "only")])
        let count = try await store.query(GuardedKeyRecord.self).count()
        #expect(count == 1)
    }
}
