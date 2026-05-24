import Foundation
import Koma
import KomaMacros

struct BenchmarkProject: Codable, Equatable {
    let id: String
    let name: String
    let slug: String
    let deletedAt: Double?
    let score: Int
    let updatedAt: Double
    let summary: String
}

@KomaEntity(table: "benchmark_projects", as: BenchmarkProject.self)
struct BenchmarkProjectRecord: KomaRemoteRecord, Equatable {
    var id: String
    var name: String
    var slug: String
    var deletedAt: Double?
    var score: Int
    var updatedAt: Double
    var summary: String
}

struct BenchmarkCharacter: Codable, Equatable {
    let id: String
    let projectId: String
    let name: String
    let role: String
}

@KomaEntity(table: "benchmark_characters", as: BenchmarkCharacter.self)
struct BenchmarkCharacterRecord: KomaRemoteRecord, Equatable {
    var id: String
    var projectId: String
    var name: String
    var role: String
}
