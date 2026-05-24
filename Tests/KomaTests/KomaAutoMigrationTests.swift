import Foundation
import Koma
import KomaSQLite
import Testing

struct KomaAutoMigrationTests {
    @Test
    func `store automatically adds missing columns`() async throws {
        let path = makeStorePath()
        defer { self.removeStore(at: path) }

        var oldStore: SQLiteKomaStore? = try await SQLiteKomaStore(path: path)
        try await oldStore?.upsert([
            MigrationProjectV1Record(id: "1", name: "Alpha")
        ])
        oldStore = nil

        let store = try await SQLiteKomaStore(path: path)
        let records = try await store.query(MigrationProjectV2Record.self)
            .fetch()

        #expect(records == [
            MigrationProjectV2Record(id: "1", name: "Alpha", slug: nil)
        ])
    }

    @Test
    func `store applies composable migration packs`() async throws {
        let path = makeStorePath()
        defer { self.removeStore(at: path) }

        var oldStore: SQLiteKomaStore? = try await SQLiteKomaStore(path: path)
        try await oldStore?.upsert([
            RenameProjectV1Record(id: "1", title: "Alpha")
        ])
        oldStore = nil

        let schema = KomaSchema(migrationPacks: [RenameProjectMigrations.self])
        let store = try await SQLiteKomaStore(path: path, schema: schema)
        let records = try await store.query(RenameProjectV2Record.self)
            .fetch()

        #expect(records == [
            RenameProjectV2Record(id: "1", name: "Alpha")
        ])
    }

    private func makeStorePath() -> String {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }

    private func removeStore(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.removeItem(atPath: "\(path)-shm")
        try? FileManager.default.removeItem(atPath: "\(path)-wal")
    }
}
