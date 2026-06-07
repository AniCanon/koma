import Foundation
import Koma
import KomaSQLite
import Testing

@KomaEntity(table: "join_projects")
private struct JoinProjectRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var deletedAt: Date?

    init(id: String, name: String, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.deletedAt = deletedAt
    }
}

@KomaEntity(table: "join_characters")
private struct JoinCharacterRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var projectId: String
    var name: String

    init(id: String, projectId: String, name: String) {
        self.id = id
        self.projectId = projectId
        self.name = name
    }
}

@KomaModel(record: JoinProjectRecord.self)
private struct JoinProjectModel {
    var id: String
    var name: String
    var deletedAt: Date?
}

struct KomaJoinTests {
    @Test
    func `record joins filter by related table and keep base rows distinct`() async throws {
        let store = try await makeSeededStore()

        let projects = try await store.query(JoinProjectRecord.self)
            .join(JoinCharacterRecord.self) { $0.id == $1.projectId }
            .where { $0.deletedAt == nil }
            .where(JoinCharacterRecord.self) { $0.name.hasPrefix("A") }
            .order(by: \.name)
            .fetch()

        #expect(projects.map(\.id) == ["p1"])

        let count = try await store.query(JoinProjectRecord.self)
            .join(JoinCharacterRecord.self) { $0.id == $1.projectId }
            .where { $0.deletedAt == nil }
            .where(JoinCharacterRecord.self) { $0.name.hasPrefix("A") }
            .count()

        #expect(count == 1)
    }

    @Test
    func `model queries support named outer joins`() async throws {
        let store = try await makeSeededStore()

        let matchingModels = try await store.query(JoinProjectModel.self)
            .join(JoinCharacterRecord.self) { $0.id == $1.projectId }
            .where(JoinCharacterRecord.self) { $0.name == "Bato" }
            .fetch()

        #expect(matchingModels.map(\.id) == ["p2"])

        let allProjects = try await store.query(JoinProjectRecord.self)
            .leftJoin(JoinCharacterRecord.self) { $0.id == $1.projectId }
            .where { $0.deletedAt == nil }
            .order(by: \.id)
            .fetch()

        #expect(allProjects.map(\.id) == ["p1", "p2", "p3"])

        let projectsWithoutCharacters = try await store.query(JoinProjectRecord.self)
            .leftJoin(JoinCharacterRecord.self) { $0.id == $1.projectId }
            .where { $0.deletedAt == nil }
            .where(JoinCharacterRecord.self) { $0.id.isNull() }
            .fetch()

        #expect(projectsWithoutCharacters.map(\.id) == ["p3"])

        let rightJoined = try await store.query(JoinProjectRecord.self)
            .rightJoin(JoinCharacterRecord.self) { $0.id == $1.projectId }
            .where(JoinCharacterRecord.self) { $0.name == "Bato" }
            .fetch()

        #expect(rightJoined.map(\.id) == ["p2"])
    }

    private func makeSeededStore() async throws -> SQLiteKomaStore {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
        let store = try await SQLiteKomaStore(path: url.path)
        try await store.upsert([
            JoinProjectRecord(id: "p1", name: "Alpha"),
            JoinProjectRecord(id: "p2", name: "Beta"),
            JoinProjectRecord(id: "p3", name: "Gamma"),
            JoinProjectRecord(id: "deleted", name: "Deleted", deletedAt: Date())
        ])
        try await store.upsert([
            JoinCharacterRecord(id: "c1", projectId: "p1", name: "Akira"),
            JoinCharacterRecord(id: "c2", projectId: "p1", name: "Asuka"),
            JoinCharacterRecord(id: "c3", projectId: "p2", name: "Bato"),
            JoinCharacterRecord(id: "ignored", projectId: "deleted", name: "Aged Out")
        ])
        return store
    }
}
