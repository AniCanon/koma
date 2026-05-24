import Foundation

public enum KomaContextError: Error, Equatable, LocalizedError {
    case missingClient

    public var errorDescription: String? {
        switch self {
        case .missingClient:
            return "No KomaClient is available in the current task context."
        }
    }
}

public enum KomaContext {
    @TaskLocal public static var currentClient: KomaClient?

    public static func withClient<Result: Sendable>(
        _ client: KomaClient,
        operation: @Sendable () async throws -> Result
    ) async rethrows -> Result {
        try await $currentClient.withValue(client) {
            try await operation()
        }
    }
}

public extension KomaResourceNamespace {
    static func client() throws -> Client {
        guard let koma = KomaContext.currentClient else {
            throw KomaContextError.missingClient
        }
        return Self.client(in: koma)
    }
}
