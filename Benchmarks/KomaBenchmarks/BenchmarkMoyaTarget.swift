import Foundation
import Moya

enum BenchmarkMoyaTarget {
    case projects
}

extension BenchmarkMoyaTarget: TargetType {
    var baseURL: URL {
        BenchmarkNetworkFixtures.baseURL
    }

    var path: String {
        "projects"
    }

    var method: Moya.Method {
        .get
    }

    var task: Task {
        .requestPlain
    }

    var headers: [String: String]? {
        ["Accept": "application/json"]
    }
}

extension MoyaProvider where Target == BenchmarkMoyaTarget {
    func requestData(_ target: Target) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.request(target) { result in
                switch result {
                case let .success(response):
                    continuation.resume(returning: response.data)
                case let .failure(error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
