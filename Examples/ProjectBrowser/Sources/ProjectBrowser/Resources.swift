import Koma

@KomaResource(basePath: "projects", record: ProjectRecord.self)
enum ProjectResources {
    @KomaRoute(
        .get(as: [Project].self),
        cache: .collection("projects", staleAfter: .minutes(5)),
        refresh: .allowed
    )
    case list(ProjectListParams = .init())

    @KomaRoute(
        .get("{projectId}", as: Project.self),
        cache: .entity("projects", staleAfter: .minutes(15)),
        refresh: .allowed
    )
    case detail(projectId: String)
}

@KomaResource(basePath: "projects", record: CharacterRecord.self)
enum ProjectCharacterResources {
    @KomaRoute(
        .get("{projectId}/characters", as: [Character].self),
        cache: .collection("project-characters", staleAfter: .minutes(15)),
        refresh: .allowed
    )
    case list(projectId: String)
}
