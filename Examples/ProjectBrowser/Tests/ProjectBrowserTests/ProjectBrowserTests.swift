import Foundation
import Koma
@testable import ProjectBrowser
import Testing

struct ProjectBrowserTests {
    @Test
    func `repository refreshes project list and reads hydrated models`() async throws {
        let environment = try await makeDemoEnvironment(responses: [
            demoProjectListResponse()
        ])

        let projects = try await environment.repository.listProjects(search: "akira")

        #expect(projects.map(\.id) == ["project-1", "project-2"])
        #expect(projects.map(\.name) == ["Akira Boards", "Sakuga Notes"])

        let requests = await environment.transport.requests
        #expect(requests.first?.path == "projects")
        #expect(requests.first?.headers["Authorization"] == "Bearer demo-token")
        #expect(requests.first?.queryItems.contains(URLQueryItem(name: "search", value: "akira")) == true)
    }

    @Test
    func `repository fetches parameterized detail and relationship resources`() async throws {
        let environment = try await makeDemoEnvironment(responses: [
            demoProjectDetailResponse(),
            demoCharacterListResponse()
        ])

        let project = try await environment.repository.project(id: "project-1")
        let activeCharacters = try await project.characters
            .where { $0.deletedAt == nil }
            .fetch()

        #expect(project.name == "Akira Boards")
        #expect(activeCharacters.map(\.name) == ["Kaneda"])

        let requests = await environment.transport.requests
        #expect(requests.map(\.path) == ["projects/project-1", "projects/project-1/characters"])
    }

    @Test
    func `refresh registrations store concrete requests without auth secrets`() async throws {
        let environment = try await makeDemoEnvironment(responses: [
            demoProjectDetailResponse(),
            demoCharacterListResponse()
        ])

        _ = try await environment.repository.project(id: "project-1")

        let registrations = try await environment.koma.refreshRegistrations()
        #expect(registrations.map(\.path).contains("projects/project-1"))
        #expect(registrations.map(\.path).contains("projects/project-1/characters"))
        #expect(!String(describing: registrations).contains("demo-token"))
    }

    @Test
    func `app code can depend on a mockable repository protocol`() async throws {
        let service: any ProjectServing = MockProjectServing()

        let projects = try await service.listProjects(search: nil)

        #expect(projects.isEmpty)
    }
}
