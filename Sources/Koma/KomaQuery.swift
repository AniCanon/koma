import Foundation

/// A lazy record query.
///
/// Add predicates, sorting, limits, and offsets before executing with `fetch()`.
///
/// ```swift
/// let records = try await store.query(ProjectRecord.self)
///     .where { $0.deletedAt == nil }
///     .order(by: \.name)
///     .limit(20)
///     .fetch()
/// ```
public struct KomaQuery<Record: KomaEntityRecord>: Sendable {
    private let store: any KomaStore
    private var request: KomaQueryRequest<Record>

    public init(store: any KomaStore, record: Record.Type) {
        self.store = store
        request = KomaQueryRequest(record: record)
    }

    /// Adds a predicate to the query.
    public func `where`(_ build: @Sendable (KomaPredicateBuilder<Record>) -> KomaPredicate) -> Self {
        var copy = self
        let predicate = build(KomaPredicateBuilder())
        if let existing = copy.request.predicate {
            copy.request.predicate = existing && predicate
        } else {
            copy.request.predicate = predicate
        }
        return copy
    }

    public func order(
        by keyPath: KeyPath<Record.Columns, KomaColumn<some Any>>,
        _ direction: KomaSortDirection = .ascending
    ) -> Self {
        var copy = self
        let column = Record.columns[keyPath: keyPath]
        copy.request.order.append(
            KomaSortDescriptor(column: column.name, columnIndex: column.index, direction: direction)
        )
        return copy
    }

    public func limit(_ limit: Int) -> Self {
        var copy = self
        copy.request.limit = limit
        return copy
    }

    public func offset(_ offset: Int) -> Self {
        var copy = self
        copy.request.offset = offset
        return copy
    }

    /// Joins another record table to this query.
    ///
    /// Joined queries still return the base record. Use `where(_:_: )` to add
    /// predicates against the joined record.
    public func join<Joined: KomaEntityRecord>(
        _ joined: Joined.Type,
        on condition: @Sendable (KomaPredicateBuilder<Record>, KomaPredicateBuilder<Joined>) -> KomaJoinCondition
    ) -> Self {
        addingJoin(joined, kind: .inner, on: condition)
    }

    /// Left joins another record table while returning the base record type.
    public func leftJoin<Joined: KomaEntityRecord>(
        _ joined: Joined.Type,
        on condition: @Sendable (KomaPredicateBuilder<Record>, KomaPredicateBuilder<Joined>) -> KomaJoinCondition
    ) -> Self {
        addingJoin(joined, kind: .left, on: condition)
    }

    /// Right joins another record table while returning the base record type.
    public func rightJoin<Joined: KomaEntityRecord>(
        _ joined: Joined.Type,
        on condition: @Sendable (KomaPredicateBuilder<Record>, KomaPredicateBuilder<Joined>) -> KomaJoinCondition
    ) -> Self {
        addingJoin(joined, kind: .right, on: condition)
    }

    /// Adds a predicate against a previously joined record table.
    public func `where`<Joined: KomaEntityRecord>(
        _ joined: Joined.Type,
        _ build: @Sendable (KomaPredicateBuilder<Joined>) -> KomaPredicate
    ) -> Self {
        var copy = self
        let predicate = build(KomaPredicateBuilder()).qualified(by: Joined.komaTableName)
        if let existing = copy.request.predicate {
            copy.request.predicate = existing && predicate
        } else {
            copy.request.predicate = predicate
        }
        return copy
    }

    /// Executes the query and returns all matching records.
    public func fetch() async throws -> [Record] {
        try await store.fetch(request)
    }

    /// Observes this query when the underlying store supports live invalidation.
    ///
    /// Stores that do not support observation emit the current query result once.
    public func observe() -> AsyncThrowingStream<[Record], Error> {
        if let observableStore = store as? any KomaObservableStore {
            return observableStore.observe(request)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await continuation.yield(fetch())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Executes the query with `LIMIT 1`.
    public func first() async throws -> Record? {
        var copy = self
        copy.request.limit = 1
        return try await copy.store.fetch(copy.request).first
    }

    public func count() async throws -> Int {
        try await store.count(request)
    }

    public func exists() async throws -> Bool {
        try await !limit(1).fetch().isEmpty
    }

    public var queryRequest: KomaQueryRequest<Record> {
        request
    }

    private func addingJoin<Joined: KomaEntityRecord>(
        _ joined: Joined.Type,
        kind: KomaJoinKind,
        on condition: @Sendable (KomaPredicateBuilder<Record>, KomaPredicateBuilder<Joined>) -> KomaJoinCondition
    ) -> Self {
        var copy = self
        copy.request.joins.append(
            KomaJoinDescriptor(
                kind: kind,
                tableName: Joined.komaTableName,
                primaryKey: Joined.komaPrimaryKey,
                columns: Joined.komaColumns,
                columnPairs: condition(KomaPredicateBuilder(), KomaPredicateBuilder()).columnPairs
            )
        )
        return copy
    }
}
