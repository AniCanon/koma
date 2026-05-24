import Foundation

/// Describes how long a concrete request should stay registered for refresh.
///
/// Attach a policy with `keepFresh(_:)` on a refreshable request:
///
/// ```swift
/// let project = try await ProjectResources.client(in: koma)
///     .detail(projectId: "123")
///     .keepFresh(.whileRecentlyViewed(days: 7, staleAfter: .minutes(15), userScope: user.id))
///     .fetch(policy: .networkFirstFallback)
/// ```
public struct KomaRefreshPolicy: Equatable, Sendable {
    public enum Lifetime: String, Equatable, Sendable {
        case whileAuthenticated
        case whileRecentlyViewed
        case untilRemoved
    }

    public let lifetime: Lifetime
    public let staleAfter: KomaDuration
    public let expiresAfter: KomaDuration?
    public let userScope: String?

    public init(
        lifetime: Lifetime,
        staleAfter: KomaDuration,
        expiresAfter: KomaDuration? = nil,
        userScope: String? = nil
    ) {
        self.lifetime = lifetime
        self.staleAfter = staleAfter
        self.expiresAfter = expiresAfter
        self.userScope = userScope
    }

    public static func whileAuthenticated(
        staleAfter: KomaDuration,
        userScope: String? = nil
    ) -> Self {
        Self(lifetime: .whileAuthenticated, staleAfter: staleAfter, userScope: userScope)
    }

    public static func whileRecentlyViewed(
        days: Double,
        staleAfter: KomaDuration,
        userScope: String? = nil
    ) -> Self {
        Self(
            lifetime: .whileRecentlyViewed,
            staleAfter: staleAfter,
            expiresAfter: .hours(days * 24),
            userScope: userScope
        )
    }

    public static func untilRemoved(
        staleAfter: KomaDuration,
        userScope: String? = nil
    ) -> Self {
        Self(lifetime: .untilRemoved, staleAfter: staleAfter, userScope: userScope)
    }
}

public enum KomaRefreshResult: Equatable, Sendable {
    case refreshed(String)
    case skipped(String, KomaRefreshSkipReason)
    case failed(String, String)
}

public enum KomaRefreshSkipReason: String, Equatable, Sendable {
    case notDue
    case expired
    case missingHandler
}

public enum KomaRefreshError: Error, Equatable, LocalizedError {
    case operationNotRefreshable(String)
    case onlyGETRequestsCanBeRefreshed(String)

    public var errorDescription: String? {
        switch self {
        case let .operationNotRefreshable(operation):
            return "\(operation) is not marked as refreshable."
        case let .onlyGETRequestsCanBeRefreshed(operation):
            return "\(operation) cannot be scheduled because only GET requests are refreshable."
        }
    }
}
