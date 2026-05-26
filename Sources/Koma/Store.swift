import Foundation

/// A storage engine capable of reading and writing normalized Koma records.
public protocol KomaStore: Sendable {
    func ensureSchema(for record: (some KomaEntityRecord).Type) async throws
    func upsert(_ records: [some KomaEntityRecord]) async throws
    func fetch<Record: KomaEntityRecord>(_ request: KomaQueryRequest<Record>) async throws -> [Record]
    func count(_ request: KomaQueryRequest<some KomaEntityRecord>) async throws -> Int
    func delete(_ request: KomaDeleteRequest<some KomaEntityRecord>) async throws -> Int
    func update(_ request: KomaUpdateRequest<some KomaEntityRecord>) async throws -> Int
    func transaction<Value: Sendable>(_ body: @Sendable (any KomaStore) async throws -> Value) async throws -> Value
}

/// A store that can keep local queries alive and emit again when matching tables change.
public protocol KomaObservableStore: KomaStore {
    func observe<Record: KomaEntityRecord>(
        _ request: KomaQueryRequest<Record>,
        observing additionalTables: Set<String>
    ) -> AsyncThrowingStream<[Record], Error>
}

/// Store-private extension point for persisting macro-scanned JSON without materializing record arrays.
@_documentation(visibility: private)
public protocol KomaFusedJSONStore: KomaStore {
    func upsertJSON(_ data: Data, record: (some KomaFusedJSONRecord).Type) async throws
}

public extension KomaObservableStore {
    func observe<Record: KomaEntityRecord>(
        _ request: KomaQueryRequest<Record>
    ) -> AsyncThrowingStream<[Record], Error> {
        observe(request, observing: [])
    }
}

public extension KomaStore {
    /// Starts a lazy record query.
    func query<Record: KomaEntityRecord>(_ record: Record.Type) -> KomaQuery<Record> {
        KomaQuery(store: self, record: record)
    }

    /// Starts a lazy delete operation.
    func delete<Record: KomaEntityRecord>(_ record: Record.Type) -> KomaDelete<Record> {
        KomaDelete(store: self, record: record)
    }

    /// Deletes a record by its primary key value.
    @discardableResult
    func delete<Record: KomaEntityRecord>(
        _ record: Record.Type,
        id: some KomaBindableValue
    ) async throws -> Int {
        let request = KomaDeleteRequest<Record>(
            record: record,
            predicate: KomaPredicate(column: Record.komaPrimaryKey, operation: .equals(id.komaValue))
        )
        return try await delete(request)
    }

    /// Starts a lazy update operation.
    func update<Record: KomaEntityRecord>(_ record: Record.Type) -> KomaUpdate<Record> {
        KomaUpdate(store: self, record: record)
    }
}
