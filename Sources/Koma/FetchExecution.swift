import Foundation

extension KomaFetch {
    func refreshPayload(
        needsOutput: Bool = true,
        needsRecords: Bool = true
    ) async throws -> (output: Output?, records: [Record]?) {
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

        let validatorKey = conditionalRequestKey()
        var storedValidator: KomaHTTPValidatorRecord?
        if let validatorKey {
            storedValidator = try await client.store.query(KomaHTTPValidatorRecord.self)
                .where { $0.id == validatorKey }
                .fetch()
                .first
            if let etag = storedValidator?.etag {
                request.headers["If-None-Match"] = etag
            }
            if let lastModified = storedValidator?.lastModified {
                request.headers["If-Modified-Since"] = lastModified
            }
        }

        let response = try await client.execute(
            request,
            operation: operation.name,
            collectResponseHeaders: !client.plugins.isEmpty || validatorKey != nil,
            acceptNotModified: storedValidator?.etag != nil || storedValidator?.lastModified != nil
        )

        // 304: the server confirmed the local store is current — skip download, decode, and
        // upsert; serve the output from local records when the caller needs one.
        if response.statusCode == 304 {
            if needsOutput || needsRecords {
                let records = try await client.store.fetch(queryRequest)
                let output: Output? = needsOutput
                    ? try KomaDefaultRemoteMapper.output(records, as: Output.self)
                    : nil
                return (output, needsRecords ? records : nil)
            }
            return (nil, nil)
        }

        let payload = try await persistPayload(
            response: response,
            needsOutput: needsOutput,
            needsRecords: needsRecords
        )

        if let validatorKey {
            try await updateValidator(for: validatorKey, previous: storedValidator, response: response)
        }
        return payload
    }

    private func persistPayload(
        response: KomaResponse,
        needsOutput: Bool,
        needsRecords: Bool
    ) async throws -> (output: Output?, records: [Record]?) {
        let context = KomaPersistenceContext(
            operationName: operation.name,
            pathValues: operation.pathValues,
            queryItems: operation.queryItems,
            cache: operation.cache
        )

        if operation.adapter == nil {
            do {
                if let jsonPayload = try await jsonPayload(
                    from: response.body,
                    needsOutput: needsOutput,
                    needsRecords: needsRecords
                ) {
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

    /// Identity of this concrete GET for validator storage, or nil when conditional requests
    /// do not apply (non-GET, bodied request, or the feature is disabled).
    private func conditionalRequestKey() -> String? {
        guard client.conditionalRequests == .automatic,
              operation.method == .get,
              operation.body == nil
        else {
            return nil
        }
        let query = operation.queryItems
            .map { "\($0.name)=\($0.value ?? "")" }
            .sorted()
            .joined(separator: "&")
        return "GET \(operation.resolvedPath)?\(query)"
    }

    private func updateValidator(
        for key: String,
        previous: KomaHTTPValidatorRecord?,
        response: KomaResponse
    ) async throws {
        let etag = response.headerValue("ETag")
        let lastModified = response.headerValue("Last-Modified")

        guard etag != nil || lastModified != nil else {
            // The server stopped sending validators; drop the stale record so future
            // refreshes do not revalidate against a dead value.
            if previous != nil {
                _ = try await client.store.delete(KomaHTTPValidatorRecord.self, id: key)
            }
            return
        }

        guard previous?.etag != etag || previous?.lastModified != lastModified else {
            return
        }
        try await client.store.upsert([
            KomaHTTPValidatorRecord(
                id: key,
                operationName: operation.name,
                etag: etag,
                lastModified: lastModified,
                updatedAt: Date()
            )
        ])
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
        from data: borrowing Data,
        needsOutput: Bool = true,
        needsRecords: Bool = true
    ) async throws -> (output: Output?, records: [Record]?)? {
        guard client.jsonOptimization == .automatic,
              let jsonRecordType = Record.self as? any KomaJSONFastPathRecord.Type
        else {
            return nil
        }

        if !needsOutput,
           !needsRecords,
           let fusedStore = client.store as? any KomaFusedJSONStore,
           let fusedRecordType = Record.self as? any KomaFusedJSONRecord.Type
        {
            try await upsertFusedJSON(data, record: fusedRecordType, store: fusedStore)
            return (nil, nil)
        }

        if Output.self == [Record.Remote].self {
            let records = try decodeJSONRecords(data, record: jsonRecordType)
            try await client.store.upsert(records)
            let output: Output? = if needsOutput {
                try KomaDefaultRemoteMapper.output(records, as: Output.self)
            } else {
                nil
            }
            return (output, needsRecords ? records : nil)
        }

        if Output.self == Record.Remote.self {
            let record = try decodeJSONRecord(data, record: jsonRecordType)
            try await client.store.upsert([record])
            let output: Output? = if needsOutput {
                try KomaDefaultRemoteMapper.output([record], as: Output.self)
            } else {
                nil
            }
            return (output, needsRecords ? [record] : nil)
        }

        return nil
    }

    private func decodeJSONRecords<FastRecord: KomaJSONFastPathRecord>(
        _ data: borrowing Data,
        record _: FastRecord.Type
    ) throws -> [Record] {
        let decoded = try FastRecord.komaJSONRecords(from: data)
        guard let records = decoded as? [Record] else {
            throw KomaMappingError.unsupportedOutput("Koma JSON fast path returned an unexpected record type.")
        }
        return records
    }

    private func decodeJSONRecord<FastRecord: KomaJSONFastPathRecord>(
        _ data: borrowing Data,
        record _: FastRecord.Type
    ) throws -> Record {
        let decoded = try FastRecord.komaJSONRecord(from: data)
        guard let record = decoded as? Record else {
            throw KomaMappingError.unsupportedOutput("Koma JSON fast path returned an unexpected record type.")
        }
        return record
    }

    private func upsertFusedJSON(
        _ data: Data,
        record: (some KomaFusedJSONRecord).Type,
        store: any KomaFusedJSONStore
    ) async throws {
        try await store.upsertJSON(data, record: record)
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
