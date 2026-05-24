import Foundation
import Koma
import KomaMacros
import KomaSQLite
import Testing

@KomaEntity(table: "query_write_items")
private struct QueryWriteItemRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var rank: Int
    var kind: String
    var deletedAt: Date?

    init(id: String, name: String, rank: Int, kind: String, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.rank = rank
        self.kind = kind
        self.deletedAt = deletedAt
    }
}

struct KomaQueryWriteTests {
    @Test
    func `richer predicates pagination and convenience reads`() async throws {
        let store = try await makeStore()
        try await store.upsert([
            QueryWriteItemRecord(id: "1", name: "Akira", rank: 1, kind: "movie"),
            QueryWriteItemRecord(id: "2", name: "Berserk", rank: 2, kind: "manga"),
            QueryWriteItemRecord(id: "3", name: "Cowboy Bebop", rank: 3, kind: "anime"),
            QueryWriteItemRecord(id: "4", name: "Dorohedoro", rank: 4, kind: "manga"),
            QueryWriteItemRecord(id: "5", name: "Evangelion", rank: 5, kind: "anime", deletedAt: Date())
        ])

        let filtered = try await store.query(QueryWriteItemRecord.self)
            .where { ($0.rank >= 2) && ($0.rank < 5) && $0.name.contains("o") }
            .order(by: \.rank, .descending)
            .fetch()

        #expect(filtered.map(\.id) == ["4", "3"])

        let paged = try await store.query(QueryWriteItemRecord.self)
            .where { $0.kind.in(["anime", "manga"]) && $0.rank.between(2, 5) }
            .order(by: \.rank)
            .offset(1)
            .limit(2)
            .fetch()

        #expect(paged.map(\.id) == ["3", "4"])

        let first = try await store.query(QueryWriteItemRecord.self)
            .where { $0.name.hasPrefix("A") }
            .first()
        #expect(first?.id == "1")

        let deletedCount = try await store.query(QueryWriteItemRecord.self)
            .where { $0.deletedAt != nil }
            .count()
        #expect(deletedCount == 1)

        let exists = try await store.query(QueryWriteItemRecord.self)
            .where { $0.name.like("%Bebop") }
            .exists()
        #expect(exists)
    }

    @Test
    func `convenience reads respect predicates ordering and empty results`() async throws {
        let store = try await makeStore()
        try await store.upsert([
            QueryWriteItemRecord(id: "1", name: "Alpha", rank: 10, kind: "anime"),
            QueryWriteItemRecord(id: "2", name: "Beta", rank: 20, kind: "anime"),
            QueryWriteItemRecord(id: "3", name: "Gamma", rank: 30, kind: "manga"),
            QueryWriteItemRecord(id: "4", name: "Archived", rank: 40, kind: "anime", deletedAt: Date())
        ])

        let firstActiveAnime = try await store.query(QueryWriteItemRecord.self)
            .where { $0.kind == "anime" && $0.deletedAt == nil }
            .order(by: \.rank, .descending)
            .first()

        #expect(firstActiveAnime?.id == "2")

        let activeAnimeCount = try await store.query(QueryWriteItemRecord.self)
            .where { $0.kind == "anime" && $0.deletedAt == nil }
            .count()

        #expect(activeAnimeCount == 2)

        let archivedAnimeExists = try await store.query(QueryWriteItemRecord.self)
            .where { $0.kind == "anime" && $0.deletedAt != nil }
            .exists()

        #expect(archivedAnimeExists)

        let missingFirst = try await store.query(QueryWriteItemRecord.self)
            .where { $0.name == "Missing" }
            .first()

        let missingExists = try await store.query(QueryWriteItemRecord.self)
            .where { $0.name == "Missing" }
            .exists()

        let missingCount = try await store.query(QueryWriteItemRecord.self)
            .where { $0.name == "Missing" }
            .count()

        #expect(missingFirst == nil)
        #expect(!missingExists)
        #expect(missingCount == 0)
    }

    @Test
    func `update delete and rollback transaction`() async throws {
        let store = try await makeStore()
        try await store.upsert([
            QueryWriteItemRecord(id: "1", name: "Draft", rank: 1, kind: "anime"),
            QueryWriteItemRecord(id: "2", name: "Deleted", rank: 2, kind: "anime", deletedAt: Date())
        ])

        let updated = try await store.update(QueryWriteItemRecord.self)
            .set(\.name, to: "Final")
            .where { $0.id == "1" }
            .execute()

        #expect(updated == 1)
        let updatedRecord = try await store.query(QueryWriteItemRecord.self)
            .where { $0.id == "1" }
            .first()
        #expect(updatedRecord?.name == "Final")

        let deleted = try await store.delete(QueryWriteItemRecord.self)
            .where { $0.deletedAt != nil }
            .execute()

        #expect(deleted == 1)
        let deletedRecordExists = try await store.query(QueryWriteItemRecord.self)
            .where { $0.id == "2" }
            .exists()
        #expect(!deletedRecordExists)

        do {
            try await store.transaction { tx in
                try await tx.upsert([
                    QueryWriteItemRecord(id: "rollback", name: "Rollback", rank: 99, kind: "test")
                ])
                throw RollbackError.expected
            }
            Issue.record("Expected transaction to roll back.")
        } catch RollbackError.expected {}

        let rolledBack = try await store.query(QueryWriteItemRecord.self)
            .where { $0.id == "rollback" }
            .exists()
        #expect(!rolledBack)
    }

    @Test
    func `delete by primary key and set optional column to nil`() async throws {
        let store = try await makeStore()
        let deletedAt = Date(timeIntervalSinceReferenceDate: 100)
        try await store.upsert([
            QueryWriteItemRecord(id: "1", name: "Active", rank: 1, kind: "anime", deletedAt: deletedAt),
            QueryWriteItemRecord(id: "2", name: "Remove", rank: 2, kind: "manga")
        ])

        let updated = try await store.update(QueryWriteItemRecord.self)
            .set(\.deletedAt, to: nil)
            .where { $0.id == "1" }
            .execute()
        #expect(updated == 1)

        let restored = try await store.query(QueryWriteItemRecord.self)
            .where { $0.id == "1" }
            .first()
        #expect(restored?.deletedAt == nil)

        let deleted = try await store.delete(QueryWriteItemRecord.self, id: "2")
        #expect(deleted == 1)

        let remaining = try await store.query(QueryWriteItemRecord.self)
            .order(by: \.id)
            .fetch()
        #expect(remaining.map(\.id) == ["1"])
    }

    @Test
    func `concurrent writes do not join another task transaction`() async throws {
        let store = try await makeStore()
        let gate = TransactionGate()

        let transaction = Task {
            do {
                try await store.transaction { tx in
                    try await tx.upsert([
                        QueryWriteItemRecord(id: "inside", name: "Inside", rank: 1, kind: "tx")
                    ])
                    await gate.open()
                    try await Task.sleep(for: .milliseconds(50))
                    throw RollbackError.expected
                }
                Issue.record("Expected transaction to roll back.")
            } catch RollbackError.expected {}
        }

        await gate.wait()
        let outsideWrite = Task {
            try await store.upsert([
                QueryWriteItemRecord(id: "outside", name: "Outside", rank: 2, kind: "tx")
            ])
        }

        try await transaction.value
        try await outsideWrite.value

        let insideExists = try await store.query(QueryWriteItemRecord.self)
            .where { $0.id == "inside" }
            .exists()
        let outsideExists = try await store.query(QueryWriteItemRecord.self)
            .where { $0.id == "outside" }
            .exists()

        #expect(!insideExists)
        #expect(outsideExists)
    }

    private func makeStore() async throws -> SQLiteKomaStore {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        return try await SQLiteKomaStore(path: url.path)
    }
}

private enum RollbackError: Error {
    case expected
}

private actor TransactionGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        isOpen = true
        let waiters = waiters
        self.waiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume()
        }
    }

    func wait() async {
        guard !isOpen else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
