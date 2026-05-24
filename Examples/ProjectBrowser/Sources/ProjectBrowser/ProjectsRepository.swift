import Koma

protocol ProjectServing: Sendable {
    func listProjects(search: String?) async throws -> [ProjectModel]
    func project(id projectID: String) async throws -> ProjectModel
    func activeCharacters(for projectID: String) async throws -> [CharacterModel]
}

struct ProjectsRepository: ProjectServing {
    private let koma: KomaClient
    private let userID: String

    init(koma: KomaClient, userID: String) {
        self.koma = koma
        self.userID = userID
    }

    func listProjects(search: String? = nil) async throws -> [ProjectModel] {
        let params = ProjectListParams(search: search)

        _ = try await projectsResource
            .list(params)
            .keepFresh(.whileAuthenticated(staleAfter: .minutes(5), userScope: userID))
            .fetch(policy: .networkFirstFallback)

        return try await koma.query(ProjectModel.self)
            .where { $0.deletedAt == nil }
            .include(\.characters)
            .order(by: \.name)
            .fetch()
    }

    func project(id projectID: String) async throws -> ProjectModel {
        _ = try await projectsResource
            .detail(projectId: projectID)
            .keepFresh(.whileRecentlyViewed(days: 7, staleAfter: .minutes(15), userScope: userID))
            .fetch(policy: .networkFirstFallback)

        _ = try await charactersResource
            .list(projectId: projectID)
            .keepFresh(.whileRecentlyViewed(days: 7, staleAfter: .minutes(15), userScope: userID))
            .fetch(policy: .networkFirstFallback)

        let project = try await koma.query(ProjectModel.self)
            .where { $0.id == projectID && $0.deletedAt == nil }
            .include(\.characters)
            .first()

        guard let project else {
            throw ProjectsRepositoryError.projectNotFound(projectID)
        }

        return project
    }

    func activeCharacters(for projectID: String) async throws -> [CharacterModel] {
        let project = try await project(id: projectID)

        return try await project.characters
            .where { $0.deletedAt == nil }
            .order(by: \.name)
            .fetch()
    }

    func restoreRefreshHandlers(recentProjectIDs: [String]) async throws {
        _ = try await projectsResource
            .list()
            .keepFresh(.whileAuthenticated(staleAfter: .minutes(5), userScope: userID))
            .fetch(policy: .localOnly)

        for projectID in recentProjectIDs {
            _ = try await projectsResource
                .detail(projectId: projectID)
                .keepFresh(.whileRecentlyViewed(days: 7, staleAfter: .minutes(15), userScope: userID))
                .fetch(policy: .localOnly)

            _ = try await charactersResource
                .list(projectId: projectID)
                .keepFresh(.whileRecentlyViewed(days: 7, staleAfter: .minutes(15), userScope: userID))
                .fetch(policy: .localOnly)
        }
    }

    func refreshDueRequestsFromBackground() async throws -> [KomaRefreshResult] {
        try await koma.refreshDueRegistrations()
    }

    func clearUserRefreshStateOnLogout() async throws {
        try await koma.clearRefreshRegistrations(userScope: userID)
    }

    private var projectsResource: ProjectResources.Client {
        ProjectResources.client(in: koma)
    }

    private var charactersResource: ProjectCharacterResources.Client {
        koma.resource(ProjectCharacterResources.self)
    }
}

struct MockProjectServing: ProjectServing {
    var listProjectsHandler: @Sendable (String?) async throws -> [ProjectModel] = { _ in [] }
    var projectHandler: @Sendable (String) async throws -> ProjectModel = { projectID in
        throw ProjectsRepositoryError.projectNotFound(projectID)
    }

    var activeCharactersHandler: @Sendable (String) async throws -> [CharacterModel] = { _ in [] }

    func listProjects(search: String? = nil) async throws -> [ProjectModel] {
        try await listProjectsHandler(search)
    }

    func project(id projectID: String) async throws -> ProjectModel {
        try await projectHandler(projectID)
    }

    func activeCharacters(for projectID: String) async throws -> [CharacterModel] {
        try await activeCharactersHandler(projectID)
    }
}

enum ProjectsRepositoryError: Error, Equatable {
    case projectNotFound(String)
}
