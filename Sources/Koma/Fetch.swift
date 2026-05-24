import Foundation

public struct KomaFetch<Output: Decodable & Sendable, Record: KomaRemoteRecord>: Sendable where Record.Remote: Decodable {
    let client: KomaClient
    let operation: KomaOperation
    var queryRequest: KomaQueryRequest<Record>
    var refreshPolicy: KomaRefreshPolicy?

    public init(
        client: KomaClient,
        operation: KomaOperation,
        output: Output.Type = Output.self,
        record: Record.Type = Record.self
    ) {
        self.client = client
        self.operation = operation
        queryRequest = KomaQueryRequest(record: record)
    }

    public func `where`(_ build: @Sendable (KomaPredicateBuilder<Record>) -> KomaPredicate) -> Self {
        var copy = self
        let predicate = build(KomaPredicateBuilder())
        if let existing = copy.queryRequest.predicate {
            copy.queryRequest.predicate = existing && predicate
        } else {
            copy.queryRequest.predicate = predicate
        }
        return copy
    }

    public func order(
        by keyPath: KeyPath<Record.Columns, KomaColumn<some Any>>,
        _ direction: KomaSortDirection = .ascending
    ) -> Self {
        var copy = self
        let column = Record.columns[keyPath: keyPath].name
        copy.queryRequest.order.append(KomaSortDescriptor(column: column, direction: direction))
        return copy
    }

    public func limit(_ limit: Int) -> Self {
        var copy = self
        copy.queryRequest.limit = limit
        return copy
    }

    public func offset(_ offset: Int) -> Self {
        var copy = self
        copy.queryRequest.offset = offset
        return copy
    }

    public func keepFresh(_ policy: KomaRefreshPolicy) -> Self {
        var copy = self
        copy.refreshPolicy = policy
        return copy
    }

    public func fetch(policy: KomaFetchPolicy = .networkFirstFallback) async throws -> KomaSnapshot<Output> {
        try await client.store.ensureSchema(for: Record.self)
        let refreshRegistrationID = try await registerRefreshIfNeeded()

        let snapshot: KomaSnapshot<Output>
        switch policy {
        case .localOnly:
            snapshot = try await read(source: .local)

        case .networkFirstFallback:
            do {
                let refreshed = try await refreshPayload()
                if let refreshedSnapshot = try snapshotFromRefreshedRecords(refreshed.records) {
                    snapshot = refreshedSnapshot
                } else {
                    snapshot = try await read(source: .network)
                }
            } catch {
                let fallback = try await read(source: .fallback, lastError: error)
                if KomaOutputInspector.isEmpty(fallback.value) {
                    throw error
                }
                snapshot = fallback
            }

        case .localThenRefresh:
            let local = try await read(source: .local)
            if !KomaOutputInspector.isEmpty(local.value) {
                snapshot = local
                break
            }
            let refreshed = try await refreshPayload()
            if let refreshedSnapshot = try snapshotFromRefreshedRecords(refreshed.records) {
                snapshot = refreshedSnapshot
            } else {
                snapshot = try await read(source: .network)
            }
        }

        if let refreshRegistrationID, snapshot.source == .network {
            try await client.refreshScheduler.markSuccess(id: refreshRegistrationID)
        }
        return snapshot
    }

    public func observe(policy: KomaFetchPolicy = .localThenRefresh) -> AsyncStream<KomaSnapshot<Output>> {
        AsyncStream { continuation in
            let task = Task {
                do {
                    try await client.store.ensureSchema(for: Record.self)

                    let local = try await read(source: .local, isRefreshing: policy != .localOnly)
                    continuation.yield(local)

                    guard policy != .localOnly else {
                        continuation.finish()
                        return
                    }

                    do {
                        try await refresh()
                        try await continuation.yield(read(source: .network))
                    } catch {
                        try await continuation.yield(read(source: .fallback, lastError: error))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    @discardableResult
    public func refresh() async throws -> Output {
        try await refreshPayload().output
    }
}
