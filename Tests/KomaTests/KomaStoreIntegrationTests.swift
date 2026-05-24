import Foundation
import Koma
import KomaMacros
import KomaSQLite
import Testing

@KomaEntity(table: "koma_fast_path_profiles")
private struct SQLiteFastPathProfileRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var nickname: String?
    var isFavorite: Bool
    var rank: Int
    var score: Double
    var createdAt: Date?

    init(
        id: String,
        name: String,
        nickname: String? = nil,
        isFavorite: Bool,
        rank: Int,
        score: Double,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.isFavorite = isFavorite
        self.rank = rank
        self.score = score
        self.createdAt = createdAt
    }
}

@KomaEntity(table: "schema_reconcile_projects")
private struct SchemaReconcileProjectRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

@KomaEntity(table: "schema_reconcile_projects")
private struct IncompatibleSchemaReconcileProjectRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var uuid: String
    var name: String

    init(uuid: String, name: String) {
        self.uuid = uuid
        self.name = name
    }
}

struct KomaStoreIntegrationTests {
    @Test
    func `store filters and orders records`() async throws {
        let store = try await makeStore()
        try await store.upsert([
            ProjectRecord(id: "2", name: "Beta", slug: "beta"),
            ProjectRecord(id: "1", name: "Alpha", slug: "alpha"),
            ProjectRecord(id: "3", name: "Deleted", slug: "deleted", deletedAt: Date())
        ])

        let records = try await store.query(ProjectRecord.self)
            .where { $0.deletedAt == nil }
            .order(by: \.name)
            .fetch()

        #expect(records.map(\.id) == ["1", "2"])
        #expect(ProjectRecord.komaTableName == "projects")
        #expect(ProjectRecord.komaPrimaryKey == "id")
        #expect(ProjectRecord.komaColumns.map(\.name) == ["id", "name", "slug", "deletedAt"])
        #expect(ProjectRecord._komaSQLiteCreateTableSQL?.contains("CREATE TABLE IF NOT EXISTS") == true)
        #expect(ProjectRecord._komaSQLiteFastPath)
    }

    @Test
    func `store hydrates bool and data records`() async throws {
        let store = try await makeStore()
        let record = FeatureRecord(id: "1", isFavorite: true, payload: Data([0, 1, 2, 255]))

        try await store.upsert([record])

        let records = try await store.query(FeatureRecord.self)
            .fetch()

        #expect(records == [record])
        #expect(!FeatureRecord._komaSQLiteFastPath)
    }

    @Test
    func `macro expanded fast path hydrates bool data and date records`() async throws {
        let store = try await makeStore()
        let record = MacroFeatureRecord(
            id: "1",
            isFavorite: true,
            payload: Data([0, 1, 2, 255]),
            createdAt: Date(timeIntervalSinceReferenceDate: 12345)
        )

        try await store.upsert([record])

        let records = try await store.query(MacroFeatureRecord.self)
            .fetch()

        #expect(MacroFeatureRecord._komaSQLiteFastPath)
        #expect(!MacroFeatureRecord._komaJSONFastPath)
        #expect(records == [record])
    }

    @Test
    func `SQ lite fast path hydrates optional scalar and date fields`() async throws {
        let store = try await makeStore()
        let records = [
            SQLiteFastPathProfileRecord(
                id: "1",
                name: "Alpha",
                isFavorite: false,
                rank: 1,
                score: 1.25
            ),
            SQLiteFastPathProfileRecord(
                id: "2",
                name: "Beta",
                nickname: "Bee",
                isFavorite: true,
                rank: 2,
                score: 9.5,
                createdAt: Date(timeIntervalSinceReferenceDate: 987.125)
            )
        ]

        try await store.upsert(records)

        let hydrated = try await store.query(SQLiteFastPathProfileRecord.self)
            .order(by: \.id)
            .fetch()

        #expect(SQLiteFastPathProfileRecord._komaSQLiteFastPath)
        #expect(hydrated == records)
    }

    @Test
    func `existing databases still reconcile schema defensively`() async throws {
        let path = makeStorePath()
        var originalStore: SQLiteKomaStore? = try await SQLiteKomaStore(path: path)
        try await originalStore?.ensureSchema(for: SchemaReconcileProjectRecord.self)
        originalStore = nil

        let reopenedStore = try await SQLiteKomaStore(path: path)
        do {
            try await reopenedStore.ensureSchema(for: IncompatibleSchemaReconcileProjectRecord.self)
            Issue.record("Expected Koma to reject an incompatible primary key on an existing table.")
        } catch let SQLiteKomaError.incompatibleSchema(message) {
            #expect(message.contains("primary key"))
        }
    }

    @Test
    func `JSON handles escapes unknown fields and dates`() throws {
        let body = Data("""
        [
          {
            "id": "1",
            "name": "Alpha\\n\\uD83C\\uDF38",
            "slug": "alpha",
            "deletedAt": null,
            "unknown": { "nested": [true, false, null, { "value": 1 }] }
          },
          {
            "id": "2",
            "name": "Quote: \\\"Koma\\\"",
            "slug": "quote",
            "deletedAt": 123.5
          }
        ]
        """.utf8)

        let records = try ProjectRecord._komaJSONRecords(from: body)

        #expect(ProjectRecord._komaJSONFastPath)
        #expect(records.map(\.id) == ["1", "2"])
        #expect(records[0].name == "Alpha\n🌸")
        #expect(records[1].name == "Quote: \"Koma\"")
        #expect(records[1].deletedAt == Date(timeIntervalSinceReferenceDate: 123.5))
    }

    private func makeStore() async throws -> SQLiteKomaStore {
        try await SQLiteKomaStore(path: makeStorePath())
    }

    private func makeStorePath() -> String {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }
}
