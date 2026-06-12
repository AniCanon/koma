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
        // Validators carry no credentials, but they are per-backend state; drop them whenever
        // registrations reset (logout, tenant switch) so revalidation starts clean.
        try await store.delete(KomaHTTPValidatorRecord.self).execute()
    }

    func refreshDueRegistrations(now: Date = Date()) async throws -> [KomaRefreshResult] {
        try await store.ensureSchema(for: KomaRefreshRegistrationRecord.self)
        let registrations = try await registrations()
        var results: [KomaRefreshResult?] = Array(repeating: nil, count: registrations.count)
        var due: [(index: Int, registration: KomaRefreshRegistrationRecord, handler: @Sendable () async throws -> Void)] = []

        for (index, registration) in registrations.enumerated() {
            guard registration.expiresAt.map({ $0 > now }) ?? true else {
                try await removeRegistration(id: registration.id)
                results[index] = .skipped(registration.id, .expired)
                continue
            }
            guard registration.isDue(now: now) else {
                results[index] = .skipped(registration.id, .notDue)
                continue
            }
            guard let handler = handlers[registration.id] else {
                results[index] = .skipped(registration.id, .missingHandler)
                continue
            }
            due.append((index, registration, handler))
        }

        // Due refreshes are independent network round-trips; running them serially can blow a
        // background-task time budget with even a handful of registrations. Fan out with
        // bounded width — store writes still serialize on the store itself. Handler errors
        // fold into a `.failed` result; a failure to persist the status record propagates.
        let store = self.store
        try await withThrowingTaskGroup(of: (Int, KomaRefreshResult).self) { group in
            let width = 4
            var nextDue = 0

            func addNextRefresh() {
                guard nextDue < due.count else {
                    return
                }
                let item = due[nextDue]
                nextDue += 1
                group.addTask {
                    var updated = item.registration
                    updated.lastAttemptAt = now
                    do {
                        try await item.handler()
                        updated.lastSuccessAt = now
                        updated.lastError = nil
                        try await store.upsert([updated])
                        return (item.index, .refreshed(item.registration.id))
                    } catch {
                        updated.lastError = String(describing: error)
                        try await store.upsert([updated])
                        return (item.index, .failed(item.registration.id, updated.lastError ?? "unknown"))
                    }
                }
            }

            for _ in 0 ..< width {
                addNextRefresh()
            }
            while let (index, result) = try await group.next() {
                results[index] = result
                addNextRefresh()
            }
        }

        return results.compactMap(\.self)
    }
}
