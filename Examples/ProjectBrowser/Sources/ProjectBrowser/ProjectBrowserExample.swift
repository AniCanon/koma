import Koma

@main
struct ProjectBrowserExample {
    static func main() async throws {
        let environment = try await makeDemoEnvironment()

        let projects = try await environment.repository.listProjects(search: "akira")
        print("Projects:", projects.map(\.name).joined(separator: ", "))

        let project = try await environment.repository.project(id: "project-1")
        let characters = try await project.characters()
        print("Characters for \(project.name):", characters.map(\.name).joined(separator: ", "))

        let activeCharacters = try await project.characters
            .where { $0.deletedAt == nil }
            .fetch()
        print("Active characters:", activeCharacters.map(\.name).joined(separator: ", "))

        let registrations = try await environment.koma.refreshRegistrations()
        print("Refresh registrations:", registrations.map(\.path).joined(separator: ", "))

        let requests = await environment.transport.requests
        print("Network requests:", requests.map(\.path).joined(separator: ", "))
    }
}
