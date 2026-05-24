import Foundation
import Koma
import KomaHTTP
import KomaSQLite
import KomaTesting

protocol AuthTokenProvider: Sendable {
    func accessToken() async throws -> String
}

struct StaticAuthTokenProvider: AuthTokenProvider {
    let token: String

    func accessToken() async throws -> String {
        token
    }
}

struct ProjectBrowserSession {
    let userID: String
    let apiBaseURL: URL
    let databasePath: String
}

struct ProjectBrowserEnvironment {
    let koma: KomaClient
    let repository: ProjectsRepository
    let transport: FakeKomaTransport
}

func makeProjectBrowserClient(
    session: ProjectBrowserSession,
    tokenProvider: any AuthTokenProvider,
    transport: any KomaTransport
) async throws -> KomaClient {
    let schema = KomaSchema(modules: [ProjectSchema.self])

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    return try await KomaClient.sqlite(
        database: .path(session.databasePath),
        schema: schema,
        baseURL: session.apiBaseURL,
        transport: transport,
        plugins: [
            .bearerAuth { try await tokenProvider.accessToken() },
            .retry(maxAttempts: 3)
        ],
        jsonEncoder: encoder,
        jsonDecoder: decoder
    )
}

func makeProjectsRepository(
    session: ProjectBrowserSession,
    tokenProvider: any AuthTokenProvider,
    transport: any KomaTransport
) async throws -> ProjectsRepository {
    let koma = try await makeProjectBrowserClient(
        session: session,
        tokenProvider: tokenProvider,
        transport: transport
    )
    return ProjectsRepository(koma: koma, userID: session.userID)
}

func makeLiveProjectsRepository(
    session: ProjectBrowserSession,
    tokenProvider: any AuthTokenProvider
) async throws -> ProjectsRepository {
    try await makeProjectsRepository(
        session: session,
        tokenProvider: tokenProvider,
        transport: URLSessionKomaTransport()
    )
}

func makeDemoEnvironment(responses: [KomaResponse]? = nil) async throws -> ProjectBrowserEnvironment {
    let transport = try FakeKomaTransport(responses: responses ?? demoResponses())
    let session = ProjectBrowserSession(
        userID: "user-1",
        apiBaseURL: URL(string: "https://api.example.com/v1")!,
        databasePath: demoDatabasePath()
    )
    let tokenProvider = StaticAuthTokenProvider(token: "demo-token")
    let koma = try await makeProjectBrowserClient(
        session: session,
        tokenProvider: tokenProvider,
        transport: transport
    )

    return ProjectBrowserEnvironment(
        koma: koma,
        repository: ProjectsRepository(koma: koma, userID: session.userID),
        transport: transport
    )
}

func demoResponses() throws -> [KomaResponse] {
    try [
        demoProjectListResponse(),
        demoProjectDetailResponse(),
        demoCharacterListResponse()
    ]
}

func demoProjectListResponse() throws -> KomaResponse {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    return try KomaResponse(
        statusCode: 200,
        body: encoder.encode([
            Project(id: "project-1", name: "Akira Boards", slug: "akira-boards", deletedAt: nil),
            Project(id: "project-2", name: "Sakuga Notes", slug: "sakuga-notes", deletedAt: nil)
        ])
    )
}

func demoProjectDetailResponse() throws -> KomaResponse {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    return try KomaResponse(
        statusCode: 200,
        body: encoder.encode(Project(id: "project-1", name: "Akira Boards", slug: "akira-boards", deletedAt: nil))
    )
}

func demoCharacterListResponse() throws -> KomaResponse {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    return try KomaResponse(
        statusCode: 200,
        body: encoder.encode([
            Character(id: "character-1", projectId: "project-1", name: "Kaneda", deletedAt: nil),
            Character(id: "character-2", projectId: "project-1", name: "Archived Character", deletedAt: Date())
        ])
    )
}

func demoDatabasePath() -> String {
    FileManager.default
        .temporaryDirectory
        .appendingPathComponent("koma-project-browser-\(UUID().uuidString)")
        .appendingPathExtension("sqlite")
        .path
}
