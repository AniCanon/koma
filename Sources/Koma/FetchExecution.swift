import Foundation

extension KomaFetch {
    func refreshPayload() async throws -> (output: Output, records: [Record]?) {
        let body = try operation.body?.data()
        var request = KomaRequest(
            method: operation.method,
            path: operation.resolvedPath,
            queryItems: operation.queryItems,
            headers: ["Accept": "application/json"],
            body: body
        )
        if request.body != nil {
            request.headers["Content-Type"] = "application/json"
        }

        let response = try await client.execute(
            request,
            operation: operation.name,
            collectResponseHeaders: !client.plugins.isEmpty
        )
        let context = KomaPersistenceContext(
            operationName: operation.name,
            pathValues: operation.pathValues,
            queryItems: operation.queryItems,
            cache: operation.cache
        )

        if operation.adapter == nil {
            do {
                if let jsonPayload = try await jsonPayload(from: response.body) {
                    return jsonPayload
                }
            } catch is KomaJSONFastPathError {
                // Fall back to the configured decoder when Koma's JSON path
                // cannot represent the response shape.
            }
        }

        let output = try client.jsonDecoder.decode(Output.self, from: response.body)
        if let adapter = operation.adapter {
            try await adapter.persistAny(output, context: context, store: client.store)
        } else {
            try await KomaDefaultRemoteMapper.persist(
                output,
                record: Record.self,
                context: context,
                store: client.store
            )
        }
        return (output, nil)
    }

    func read(
        source: KomaSnapshotSource,
        isRefreshing: Bool = false,
        lastError: Error? = nil
    ) async throws -> KomaSnapshot<Output> {
        let records = try await client.store.fetch(queryRequest)
        let output: Output = try KomaDefaultRemoteMapper.output(records, as: Output.self)
        return KomaSnapshot(
            value: output,
            source: source,
            cachedAt: Date(),
            isRefreshing: isRefreshing,
            lastError: lastError
        )
    }

    func snapshot(
        value: Output,
        source: KomaSnapshotSource,
        isRefreshing: Bool = false,
        lastError: Error? = nil
    ) -> KomaSnapshot<Output> {
        KomaSnapshot(
            value: value,
            source: source,
            cachedAt: Date(),
            isRefreshing: isRefreshing,
            lastError: lastError
        )
    }

    func jsonPayload(
        from data: borrowing Data
    ) async throws -> (output: Output, records: [Record]?)? {
        guard client.jsonOptimization == .automatic,
              let jsonRecordType = Record.self as? any KomaJSONFastPathRecord.Type
        else {
            return nil
        }

        if Output.self == [Record.Remote].self {
            let decoded = try jsonRecordType.komaJSONRecordValues(from: data)
            guard let records = decoded as? [Record] else {
                throw KomaMappingError.unsupportedOutput("Koma JSON fast path returned an unexpected record type.")
            }
            try await client.store.upsert(records)
            let output: Output = try KomaDefaultRemoteMapper.output(records, as: Output.self)
            return (output, records)
        }

        if Output.self == Record.Remote.self {
            let decoded = try jsonRecordType.komaJSONRecordValue(from: data)
            guard let record = decoded as? Record else {
                throw KomaMappingError.unsupportedOutput("Koma JSON fast path returned an unexpected record type.")
            }
            try await client.store.upsert([record])
            let output: Output = try KomaDefaultRemoteMapper.output([record], as: Output.self)
            return (output, [record])
        }

        return nil
    }

    func snapshotFromRefreshedRecords(_ records: [Record]?) throws -> KomaSnapshot<Output>? {
        guard let records,
              Output.self == [Record.Remote].self || Output.self == Record.Remote.self
        else {
            return nil
        }

        let queried = try KomaInMemoryQueryEvaluator.apply(queryRequest, to: records)
        let output: Output = try KomaDefaultRemoteMapper.output(queried, as: Output.self)
        return snapshot(value: output, source: .network)
    }

    func registerRefreshIfNeeded() async throws -> String? {
        guard let refreshPolicy else {
            return nil
        }
        guard operation.isRefreshable else {
            throw KomaRefreshError.operationNotRefreshable(operation.name)
        }
        guard operation.method == .get else {
            throw KomaRefreshError.onlyGETRequestsCanBeRefreshed(operation.name)
        }

        let registration = KomaRefreshRegistrationFactory.make(
            operation: operation,
            policy: refreshPolicy
        )
        let refresh = withoutRefreshRegistration()
        try await client.refreshScheduler.register(registration) {
            _ = try await refresh.refresh()
        }
        return registration.id
    }

    func withoutRefreshRegistration() -> Self {
        var copy = self
        copy.refreshPolicy = nil
        return copy
    }
}
