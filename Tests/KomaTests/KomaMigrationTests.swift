import Foundation
import Koma
import KomaSQLite
import Testing

@KomaEntity(table: "modular_old_items")
private struct ModularItemV1Record: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var title: String
    var legacy: String

    init(id: String, title: String, legacy: String) {
        self.id = id
        self.title = title
        self.legacy = legacy
    }
}

@KomaEntity(table: "modular_items")
private struct ModularItemV2Record: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var category: String

    init(id: String, name: String, category: String) {
        self.id = id
        self.name = name
        self.category = category
    }
}

@KomaEntity(table: "modular_audits")
private struct ModularAuditRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var message: String

    init(id: String, message: String) {
        self.id = id
        self.message = message
    }
}

private enum ModularItemMigrations: KomaMigrationPack {
    static let namespace = "modular.items"

    static let migrations = [
        Migration(1, 2) {
            RenameTable(from: "modular_old_items", to: ModularItemV2Record.komaTableName)
            RenameColumn(ModularItemV2Record.self, from: "title", to: \.name)
            DropColumn(ModularItemV2Record.self, "legacy")
            AddColumn(ModularItemV2Record.self, \.category, storage: .text, default: .string("general"))
            CreateTable(ModularAuditRecord.self)
        }
    ]
}

private enum ModularItemSchema: KomaSchemaModule {
    static let entities: [any KomaEntityRecord.Type] = [
        ModularItemV2Record.self,
        ModularAuditRecord.self
    ]

    static var migrationPacks: [any KomaMigrationPack.Type] {
        [
            ModularItemMigrations.self
        ]
    }
}

struct KomaMigrationTests {
    @Test
    func `schema modules apply focused migration steps`() async throws {
        let path = makeStorePath()

        var oldStore: SQLiteKomaStore? = try await SQLiteKomaStore(path: path)
        try await oldStore?.upsert([
            ModularItemV1Record(id: "1", title: "Alpha", legacy: "remove-me")
        ])
        oldStore = nil

        let schema = KomaSchema(modules: [ModularItemSchema.self])
        let store = try await SQLiteKomaStore(path: path, schema: schema)

        let migrated = try await store.query(ModularItemV2Record.self)
            .fetch()
        #expect(migrated == [
            ModularItemV2Record(id: "1", name: "Alpha", category: "general")
        ])

        try await store.upsert([
            ModularAuditRecord(id: "audit-1", message: "created")
        ])
        let audits = try await store.query(ModularAuditRecord.self)
            .fetch()
        #expect(audits == [
            ModularAuditRecord(id: "audit-1", message: "created")
        ])
    }

    private func makeStorePath() -> String {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }
}
