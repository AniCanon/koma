import Foundation

actor KomaRefreshScheduler {
    private let store: any KomaStore
    private var handlers: [String: @Sendable () async throws -> Void] = [:]

    init(store: any KomaStore) {
        self.store = store
    }

    func register(
        _ registration: KomaRefreshRegistrationRecord,
        handler: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await store.ensureSchema(for: KomaRefreshRegistrationRecord.self)
        try await store.upsert([registration])
        handlers[registration.id] = handler
    }

    func registrations() async throws -> [KomaRefreshRegistrationRecord] {
        try await store.ensureSchema(for: KomaRefreshRegistrationRecord.self)
        return try await store.query(KomaRefreshRegistrationRecord.self)
            .order(by: \.lastRegisteredAt)
            .fetch()
    }

    func removeRegistration(id: String) async throws {
        try await store.delete(KomaRefreshRegistrationRecord.self, id: id)
        handlers[id] = nil
    }

    func markSuccess(id: String, at date: Date = Date()) async throws {
        try await store.update(KomaRefreshRegistrationRecord.self)
            .set(\.lastSuccessAt, to: date)
            .set(\.lastError, to: nil)
            .where { $0.id == id }
            .execute()
    }

    func clearRegistrations(userScope: String? = nil) async throws {
        handlers.removeAll()
        if let userScope {
            try await store.delete(KomaRefreshRegistrationRecord.self)
                .where { $0.userScope == userScope }
                .execute()
        } else {
            try await store.delete(KomaRefreshRegistrationRecord.self)
                .execute()
        }
    }

    func refreshDueRegistrations(now: Date = Date()) async throws -> [KomaRefreshResult] {
        try await store.ensureSchema(for: KomaRefreshRegistrationRecord.self)
        let registrations = try await registrations()
        var results: [KomaRefreshResult] = []

        for registration in registrations {
            guard registration.expiresAt.map({ $0 > now }) ?? true else {
                try await removeRegistration(id: registration.id)
                results.append(.skipped(registration.id, .expired))
                continue
            }
            guard registration.isDue(now: now) else {
                results.append(.skipped(registration.id, .notDue))
                continue
            }
            guard let handler = handlers[registration.id] else {
                results.append(.skipped(registration.id, .missingHandler))
                continue
            }

            var updated = registration
            updated.lastAttemptAt = now
            do {
                try await handler()
                updated.lastSuccessAt = now
                updated.lastError = nil
                try await store.upsert([updated])
                results.append(.refreshed(registration.id))
            } catch {
                updated.lastError = String(describing: error)
                try await store.upsert([updated])
                results.append(.failed(registration.id, updated.lastError ?? "unknown"))
            }
        }

        return results
    }
}
