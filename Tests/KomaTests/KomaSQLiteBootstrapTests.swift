import Foundation
import Koma
import KomaHTTP
import KomaSQLite
import KomaTesting
import Testing

struct KomaSQLiteBootstrapTests {
    @Test
    func `opens store from database location`() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("koma.sqlite")

        let store = try await SQLiteKomaStore.open(database: .url(url))
        try await store.upsert([
            ProjectRecord(id: "1", name: "Alpha", slug: "alpha")
        ])

        let projects = try await store.query(ProjectRecord.self).fetch()

        #expect(projects.map(\.id) == ["1"])
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test
    func `creates client from sqlite database location`() async throws {
        let databasePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("koma.sqlite")
            .path
        let transport = FakeKomaTransport()

        let koma = try await KomaClient.sqlite(
            database: .path(databasePath),
            baseURL: #require(URL(string: "https://example.com/v1")),
            transport: transport
        )

        try await koma.store.upsert([
            ProjectRecord(id: "1", name: "Alpha", slug: "alpha")
        ])

        let projects = try await koma.store.query(ProjectRecord.self).fetch()

        #expect(projects.map(\.id) == ["1"])
        #expect(FileManager.default.fileExists(atPath: databasePath))
    }

    @Test
    func `creates url session client from sqlite database location`() async throws {
        let databasePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("koma.sqlite")
            .path

        let koma = try await KomaClient.sqlite(
            database: .path(databasePath),
            baseURL: #require(URL(string: "https://example.com/v1"))
        )

        try await koma.store.upsert([
            ProjectRecord(id: "1", name: "Alpha", slug: "alpha")
        ])

        let projects = try await koma.store.query(ProjectRecord.self).fetch()

        #expect(projects.map(\.id) == ["1"])
        #expect(FileManager.default.fileExists(atPath: databasePath))
    }

    @Test
    func `rejects invalid database locations`() async throws {
        do {
            _ = try await SQLiteKomaStore.open(database: .path(" "))
            Issue.record("Expected empty path to be rejected.")
        } catch KomaSQLiteDatabaseError.emptyPath {
        } catch {
            Issue.record("Expected empty path error, got \(error).")
        }

        let remoteURL = try #require(URL(string: "https://example.com/koma.sqlite"))
        do {
            _ = try await SQLiteKomaStore.open(database: .url(remoteURL))
            Issue.record("Expected non-file URL to be rejected.")
        } catch let KomaSQLiteDatabaseError.nonFileURL(url) where url == remoteURL {
        } catch {
            Issue.record("Expected non-file URL error, got \(error).")
        }
    }
}
