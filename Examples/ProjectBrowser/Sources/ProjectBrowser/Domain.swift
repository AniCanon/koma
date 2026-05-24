import Foundation

struct Project: Codable, Equatable {
    let id: String
    let name: String
    let slug: String
    let deletedAt: Date?
}

struct Character: Codable, Equatable {
    let id: String
    let projectId: String
    let name: String
    let deletedAt: Date?
}

struct ProjectListParams: Codable, Equatable {
    var search: String?
    var page: Int
    var perPage: Int
    var includeDeleted: Bool

    init(
        search: String? = nil,
        page: Int = 1,
        perPage: Int = 50,
        includeDeleted: Bool = false
    ) {
        self.search = search
        self.page = page
        self.perPage = perPage
        self.includeDeleted = includeDeleted
    }
}
