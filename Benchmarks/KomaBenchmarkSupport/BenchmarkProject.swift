import Foundation
import Koma
import KomaMacros

public struct BenchmarkProject: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let slug: String
    public let deletedAt: Double?
    public let score: Int
    public let updatedAt: Double
    public let summary: String

    public init(
        id: String,
        name: String,
        slug: String,
        deletedAt: Double?,
        score: Int,
        updatedAt: Double,
        summary: String
    ) {
        self.id = id
        self.name = name
        self.slug = slug
        self.deletedAt = deletedAt
        self.score = score
        self.updatedAt = updatedAt
        self.summary = summary
    }
}

@KomaEntity(table: "benchmark_projects", as: BenchmarkProject.self)
public struct BenchmarkProjectRecord: KomaRemoteRecord, Equatable {
    public var id: String
    public var name: String
    public var slug: String
    public var deletedAt: Double?
    public var score: Int
    public var updatedAt: Double
    public var summary: String
}

public struct BenchmarkCharacter: Codable, Equatable, Sendable {
    public let id: String
    public let projectId: String
    public let name: String
    public let role: String

    public init(id: String, projectId: String, name: String, role: String) {
        self.id = id
        self.projectId = projectId
        self.name = name
        self.role = role
    }
}

@KomaEntity(table: "benchmark_characters", as: BenchmarkCharacter.self)
public struct BenchmarkCharacterRecord: KomaRemoteRecord, Equatable {
    public var id: String
    public var projectId: String
    public var name: String
    public var role: String
}
