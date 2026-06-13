import Foundation
import Koma
import KomaSQLite
import Testing

@KomaEntity(table: "pooled_items")
private struct PooledItemRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var rank: Int

    init(id: String, name: String, rank: Int) {
        self.id = id
        self.name = name
        self.rank = rank
    }
}

struct KomaReadPoolTests {
    private func makeStore() async throws -> SQLiteKomaStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("koma-readpool-\(UUID().uuidString).sqlite").path
        return try await SQLiteKomaStore(path: path)
    }

    @Test
    func `reads during an open transaction see the last committed snapshot without blocking`() async throws {
        let store = try await makeStore()
        try await store.upsert([PooledItemRecord(id: "a", name: "before", rank: 1)])

        let transactionStarted = AsyncStream.makeStream(of: Void.self)
        let releaseTransaction = AsyncStream.makeStream(of: Void.self)

        let transaction = Task {
            try await store.transaction { transactionStore in
                try await transactionStore.upsert([PooledItemRecord(id: "a", name: "during", rank: 2)])
                transactionStarted.continuation.yield(())
                for await _ in releaseTransaction.stream {
                    break
                }
                return true
            }
        }

        var iterator = transactionStarted.stream.makeAsyncIterator()
        _ = await iterator.next()

        // The transaction is open and holds an uncommitted write. A pooled read must return
        // the previous committed state immediately rather than queueing behind the commit.
        let duringTransaction = try await withObservationTimeout(.seconds(5)) {
            try await store.query(PooledItemRecord.self).fetch()
        }
        #expect(duringTransaction == [PooledItemRecord(id: "a", name: "before", rank: 1)])

        releaseTransaction.continuation.yield(())
        _ = try await transaction.value

        let afterCommit = try await store.query(PooledItemRecord.self).fetch()
        #expect(afterCommit == [PooledItemRecord(id: "a", name: "during", rank: 2)])
    }

    @Test
    func `reads inside a transaction observe its uncommitted writes`() async throws {
        let store = try await makeStore()
        try await store.upsert([PooledItemRecord(id: "a", name: "before", rank: 1)])

        try await store.transaction { transactionStore in
            try await transactionStore.upsert([PooledItemRecord(id: "a", name: "during", rank: 2)])
            let request = KomaQueryRequest(record: PooledItemRecord.self)
            let inside = try await transactionStore.fetch(request)
            #expect(inside == [PooledItemRecord(id: "a", name: "during", rank: 2)])
        }
    }

    @Test
    func `concurrent pooled reads return consistent results`() async throws {
        let store = try await makeStore()
        let records = (0 ..< 500).map { PooledItemRecord(id: "row-\($0)", name: "n\($0)", rank: $0) }
        try await store.upsert(records)

        try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 16 {
                group.addTask {
                    try await store.query(PooledItemRecord.self).fetch().count
                }
            }
            for try await count in group {
                #expect(count == 500)
            }
        }
    }

    @Test
    func `raw queries and searches work through the pool`() async throws {
        let store = try await makeStore()
        try await store.upsert([
            PooledItemRecord(id: "a", name: "semantic search note", rank: 1),
            PooledItemRecord(id: "b", name: "unrelated", rank: 2)
        ])

        let rows = try await store.rawQuery("SELECT COUNT(*) AS total FROM pooled_items")
        #expect(try rows[0].int("total") == 2)

        try await store.createFullTextIndex(for: PooledItemRecord.self, indexing: \.name)
        let matches = try await store.fullTextSearch(PooledItemRecord.self, matching: "semantic")
        #expect(matches.map(\.id) == ["a"])
    }
}
