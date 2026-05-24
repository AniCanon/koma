import Foundation
import KomaBenchmarkSupport

enum BenchmarkNetworkFixtures {
    static let baseURL = URL(string: "https://benchmark.invalid")!
    static let payload10 = Payload(label: "10", path: "projects-10", projects: BenchmarkFixtures.projects(10))
    static let payload1k = Payload(label: "1k", path: "projects", projects: BenchmarkFixtures.projects(1000))
    static let payload10k = Payload(label: "10k", path: "projects-10k", projects: BenchmarkFixtures.projects(10000))
    static let payloads = [payload10, payload1k, payload10k]
    static let restBody = payload1k.body
    static let graphQLBody = BenchmarkFixtures.graphQLResponseBody(projects: payload1k.projects)

    static func urlSession() -> URLSession {
        URLSession(configuration: urlSessionConfiguration())
    }

    static func urlSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BenchmarkURLProtocol.self]
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return configuration
    }

    static func body(for url: URL) -> Data {
        if url.path.contains("graphql") {
            return graphQLBody
        }
        if let payload = payloads.first(where: { url.lastPathComponent == $0.path }) {
            return payload.body
        }
        return restBody
    }

    struct Payload {
        let label: String
        let path: String
        let projects: [BenchmarkProject]
        let body: Data
        let url: URL

        init(label: String, path: String, projects: [BenchmarkProject]) {
            self.label = label
            self.path = path
            self.projects = projects
            body = BenchmarkFixtures.responseBody(projects: projects)
            url = BenchmarkNetworkFixtures.baseURL.appendingPathComponent(path)
        }
    }
}
