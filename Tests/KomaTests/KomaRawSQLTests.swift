import Foundation
import Koma
import KomaMacros
import KomaSQLite
import Testing

@KomaEntity(table: "raw_people")
private struct RawPersonRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var age: Int

    init(id: String, name: String, age: Int) {
        self.id = id
        self.name = name
        self.age = age
    }
}

struct KomaRawSQLTests {
    private func makeStore() async throws -> SQLiteKomaStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("koma-rawsql-\(UUID().uuidString).sqlite").path
        return try await SQLiteKomaStore(path: path)
    }

    @Test
    func `rawQuery returns a row with an int column read by name`() async throws {
        let store = try await makeStore()
        let rows = try await store.rawQuery("SELECT 42 AS answer")
        #expect(rows.count == 1)
        #expect(try rows[0].int("answer") == 42)
    }

    @Test
    func `rawQuery row exposes typed accessors by name`() async throws {
        let store = try await makeStore()
        let rows = try await store.rawQuery(
            "SELECT 'hi' AS s, 3.5 AS d, 1 AS flag, x'DEADBEEF' AS b, NULL AS missing"
        )
        let row = rows[0]
        #expect(try row.string("s") == "hi")
        #expect(try row.double("d") == 3.5)
        #expect(try row.bool("flag") == true)
        #expect(try row.data("b") == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        #expect(try row.optionalString("missing") == nil)
        #expect(try row.optionalDouble("d") == 3.5)
    }

    @Test
    func `rawExecute binds arguments and returns the change count`() async throws {
        let store = try await makeStore()
        try await store.rawExecute("CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT)")

        let inserted = try await store.rawExecute(
            "INSERT INTO t (id, name) VALUES (?, ?)",
            arguments: [1, "alice"]
        )
        #expect(inserted == 1)

        let rows = try await store.rawQuery("SELECT name FROM t WHERE id = ?", arguments: [1])
        #expect(try rows[0].string("name") == "alice")
    }

    @Test
    func `typed rawQuery decodes rows into records`() async throws {
        let store = try await makeStore()
        try await store.ensureSchema(for: RawPersonRecord.self)
        try await store.upsert([RawPersonRecord(id: "1", name: "Ada", age: 36)])

        let people = try await store.rawQuery(
            RawPersonRecord.self,
            "SELECT id, name, age FROM raw_people WHERE age > ? ORDER BY name",
            arguments: [30]
        )
        #expect(people == [RawPersonRecord(id: "1", name: "Ada", age: 36)])
    }

    @Test
    func `blob arguments round-trip byte-for-byte`() async throws {
        let store = try await makeStore()
        try await store.rawExecute("CREATE TABLE vectors (id INTEGER PRIMARY KEY, embedding BLOB)")

        let vector: [Double] = [0.1, -0.2, 0.3, 0.4]
        let bytes = vector.withUnsafeBytes { Data($0) }
        try await store.rawExecute(
            "INSERT INTO vectors (id, embedding) VALUES (?, ?)",
            arguments: [1, .blob(bytes)]
        )

        let read = try await store.rawQuery("SELECT embedding FROM vectors WHERE id = ?", arguments: [1])[0].data("embedding")
        #expect(read == bytes)
        let decoded = read.withUnsafeBytes { Array($0.bindMemory(to: Double.self)) }
        #expect(decoded == vector)
    }

    @Test
    func `raw writes participate in a transaction and roll back on error`() async throws {
        let store = try await makeStore()
        try await store.rawExecute("CREATE TABLE t (id INTEGER PRIMARY KEY)")

        struct Boom: Error {}
        await #expect(throws: Boom.self) {
            try await store.transaction { _ in
                try await store.rawExecute("INSERT INTO t (id) VALUES (1)")
                throw Boom()
            }
        }

        let count = try await store.rawQuery("SELECT COUNT(*) AS n FROM t")[0].int("n")
        #expect(count == 0)
    }

    @Test
    func `full-text search works via raw SQL with FTS5 MATCH and bm25 ranking`() async throws {
        let store = try await makeStore()
        try await store.rawExecute("CREATE VIRTUAL TABLE memories USING fts5(content)")
        try await store.rawExecute(
            "INSERT INTO memories (rowid, content) VALUES (?, ?)",
            arguments: [1, "vector search with embeddings"]
        )
        try await store.rawExecute(
            "INSERT INTO memories (rowid, content) VALUES (?, ?)",
            arguments: [2, "cooking pasta recipes"]
        )

        let hits = try await store.rawQuery(
            "SELECT rowid, bm25(memories) AS score FROM memories WHERE memories MATCH ? ORDER BY score",
            arguments: ["embeddings"]
        )
        #expect(hits.count == 1)
        #expect(try hits[0].int("rowid") == 1)
    }
}
