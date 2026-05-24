import Foundation
import Koma
import KomaMacros
import KomaSQLite
import Testing

@KomaEntity(table: "relationship_projects")
private struct RelationshipProjectRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var deletedAt: Date?

    init(id: String, name: String, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.deletedAt = deletedAt
    }
}

@KomaEntity(table: "relationship_characters")
private struct RelationshipCharacterRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var projectId: String
    var name: String
    var deletedAt: Date?

    init(id: String, projectId: String, name: String, deletedAt: Date? = nil) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.deletedAt = deletedAt
    }
}

@KomaEntity(table: "relationship_profiles")
private struct RelationshipProfileRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var projectId: String
    var synopsis: String

    init(id: String, projectId: String, synopsis: String) {
        self.id = id
        self.projectId = projectId
        self.synopsis = synopsis
    }
}

@KomaModel(record: RelationshipProfileRecord.self)
private struct RelationshipProfileModel {
    var id: String
    var projectId: String
    var synopsis: String
}

@KomaModel(record: RelationshipCharacterRecord.self)
private struct RelationshipCharacterModel {
    var id: String
    var projectId: String
    var name: String
    var deletedAt: Date?

    enum Relations {
        @KomaBelongsTo(
            RelationshipProjectRecord.self,
            local: \RelationshipCharacterRecord.Columns.projectId,
            foreign: \RelationshipProjectRecord.Columns.id,
            model: RelationshipProjectModel.self
        )
        case project
    }
}

@KomaModel(record: RelationshipProjectRecord.self)
private struct RelationshipProjectModel {
    var id: String
    var name: String
    var deletedAt: Date?

    enum Relations {
        @KomaHasMany(
            RelationshipCharacterRecord.self,
            local: \RelationshipProjectRecord.Columns.id,
            foreign: \RelationshipCharacterRecord.Columns.projectId,
            model: RelationshipCharacterModel.self
        )
        case characters

        @KomaHasOne(
            RelationshipProfileRecord.self,
            local: \RelationshipProjectRecord.Columns.id,
            foreign: \RelationshipProfileRecord.Columns.projectId,
            model: RelationshipProfileModel.self
        )
        case profile
    }
}

struct KomaRelationshipTests {
    @Test
    func `lazy relationship access memoizes inside graph context`() async throws {
        let store = try await makeSeededStore()

        let projectResult = try await store.query(RelationshipProjectModel.self)
            .where { $0.id == "p1" }
            .first()
        let project = try #require(projectResult)

        let fetchesBeforeAccess = await store.fetchCount(for: RelationshipCharacterRecord.komaTableName)
        #expect(fetchesBeforeAccess == 0)

        let firstAccess = try await project.characters.fetch()
        #expect(Set(firstAccess.map(\.id)) == ["c1", "c2"])
        let fetchesAfterFirstAccess = await store.fetchCount(for: RelationshipCharacterRecord.komaTableName)
        #expect(fetchesAfterFirstAccess == 1)

        let secondAccess = try await project.characters()
        #expect(Set(secondAccess.map(\.id)) == ["c1", "c2"])
        let fetchesAfterSecondAccess = await store.fetchCount(for: RelationshipCharacterRecord.komaTableName)
        #expect(fetchesAfterSecondAccess == 1)
    }

    @Test
    func `include batch loads relations and advanced relation query still composes`() async throws {
        let store = try await makeSeededStore()

        let projects = try await store.query(RelationshipProjectModel.self)
            .where { $0.deletedAt == nil }
            .include(\.characters)
            .order(by: \.name)
            .fetch()

        #expect(projects.map(\.id) == ["p1", "p2"])
        let projectFetches = await store.fetchCount(for: RelationshipProjectRecord.komaTableName)
        let characterFetches = await store.fetchCount(for: RelationshipCharacterRecord.komaTableName)
        #expect(projectFetches == 1)
        #expect(characterFetches == 1)

        let p1Characters = try await projects[0].characters.fetch()
        #expect(Set(p1Characters.map(\.id)) == ["c1", "c2"])
        let characterFetchesAfterLazyAccess = await store.fetchCount(for: RelationshipCharacterRecord.komaTableName)
        #expect(characterFetchesAfterLazyAccess == 1)

        let activeCharacters = try await projects[0].characters
            .where { $0.deletedAt == nil }
            .order(by: \.name)
            .fetch()

        #expect(activeCharacters.map(\.id) == ["c1"])
        let characterFetchesAfterQuery = await store.fetchCount(for: RelationshipCharacterRecord.komaTableName)
        #expect(characterFetchesAfterQuery == 2)
    }

    @Test
    func `to one relations support lazy access include and inverse belongs to`() async throws {
        let store = try await makeSeededStore()

        let projects = try await store.query(RelationshipProjectModel.self)
            .where { $0.deletedAt == nil }
            .include(\.profile)
            .order(by: \.name)
            .fetch()

        #expect(projects.map(\.id) == ["p1", "p2"])
        #expect(await store.fetchCount(for: RelationshipProfileRecord.komaTableName) == 1)

        let p1Profile = try await projects[0].profile()
        #expect(p1Profile?.synopsis == "Main project")
        let p2Profile = try await projects[1].profile.fetch()
        #expect(p2Profile?.id == nil)
        #expect(await store.fetchCount(for: RelationshipProfileRecord.komaTableName) == 1)

        let character = try #require(
            try await store.query(RelationshipCharacterModel.self)
                .where { $0.id == "c1" }
                .first()
        )
        let parent = try await character.project()
        #expect(parent?.id == "p1")
        #expect(await store.fetchCount(for: RelationshipProjectRecord.komaTableName) == 2)
    }

    private func makeSeededStore() async throws -> CountingStore {
        let base = try await SQLiteKomaStore(path: makeStorePath())
        let store = CountingStore(base: base)
        try await store.upsert([
            RelationshipProjectRecord(id: "p2", name: "Beta"),
            RelationshipProjectRecord(id: "p1", name: "Alpha"),
            RelationshipProjectRecord(id: "deleted", name: "Deleted", deletedAt: Date())
        ])
        try await store.upsert([
            RelationshipCharacterRecord(id: "c1", projectId: "p1", name: "Akira"),
            RelationshipCharacterRecord(id: "c2", projectId: "p1", name: "Archived", deletedAt: Date()),
            RelationshipCharacterRecord(id: "c3", projectId: "p2", name: "Bato"),
            RelationshipCharacterRecord(id: "ignored", projectId: "deleted", name: "Ignored")
        ])
        try await store.upsert([
            RelationshipProfileRecord(id: "profile-p1", projectId: "p1", synopsis: "Main project")
        ])
        return store
    }

    private func makeStorePath() -> String {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }
}
