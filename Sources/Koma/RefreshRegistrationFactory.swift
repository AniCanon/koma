import Foundation

enum KomaRefreshRegistrationFactory {
    static func make(
        operation: KomaOperation,
        policy: KomaRefreshPolicy,
        now: Date = Date()
    ) -> KomaRefreshRegistrationRecord {
        let query = queryString(operation.queryItems)
        let id = [
            policy.userScope ?? "global",
            operation.method.rawValue,
            operation.resolvedPath,
            query
        ].joined(separator: "|")

        return KomaRefreshRegistrationRecord(
            id: id,
            operationName: operation.name,
            method: operation.method.rawValue,
            path: operation.resolvedPath,
            query: query,
            cacheNamespace: operation.resolvedCacheNamespace,
            policyLifetime: policy.lifetime.rawValue,
            staleAfterSeconds: policy.staleAfter.seconds,
            userScope: policy.userScope,
            expiresAt: policy.expiresAfter.map { now.addingTimeInterval($0.seconds) },
            lastRegisteredAt: now
        )
    }

    private static func queryString(_ queryItems: [URLQueryItem]) -> String {
        let sorted = queryItems.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return (lhs.value ?? "") < (rhs.value ?? "")
            }
            return lhs.name < rhs.name
        }
        var components = URLComponents()
        components.queryItems = sorted
        return components.percentEncodedQuery ?? ""
    }
}
