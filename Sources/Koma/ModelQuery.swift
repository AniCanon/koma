import Foundation

/// A lazy query that returns hydrated models instead of raw records.
///
/// Include relationships to batch-load related records and avoid N+1 queries.
///
/// ```swift
/// let projects = try await koma.query(ProjectModel.self)
///     .where { $0.deletedAt == nil }
///     .include(\.characters)
///     .fetch()
/// ```
public struct KomaModelQuery<Model: KomaModel>: @unchecked Sendable {
    private let store: any KomaStore
    private var request: KomaQueryRequest<Model.Record>
    private var includes: [([Model.Record], KomaGraphContext) async throws -> Void] = []

    public init(store: any KomaStore, model: Model.Type) {
        self.store = store
        request = KomaQueryRequest(record: Model.Record.self)
    }

    public func `where`(_ build: @Sendable (KomaPredicateBuilder<Model.Record>) -> KomaPredicate) -> Self {
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
        by keyPath: KeyPath<Model.Record.Columns, KomaColumn<some Any>>,
        _ direction: KomaSortDirection = .ascending
    ) -> Self {
        var copy = self
        let column = Model.Record.columns[keyPath: keyPath].name
        copy.request.order.append(KomaSortDescriptor(column: column, direction: direction))
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

    public func join<Joined: KomaEntityRecord>(
        _ joined: Joined.Type,
        on condition: @Sendable (KomaPredicateBuilder<Model.Record>, KomaPredicateBuilder<Joined>) -> KomaJoinCondition
    ) -> Self {
        addingJoin(joined, kind: .inner, on: condition)
    }

    public func leftJoin<Joined: KomaEntityRecord>(
        _ joined: Joined.Type,
        on condition: @Sendable (KomaPredicateBuilder<Model.Record>, KomaPredicateBuilder<Joined>) -> KomaJoinCondition
    ) -> Self {
        addingJoin(joined, kind: .left, on: condition)
    }

    public func rightJoin<Joined: KomaEntityRecord>(
        _ joined: Joined.Type,
        on condition: @Sendable (KomaPredicateBuilder<Model.Record>, KomaPredicateBuilder<Joined>) -> KomaJoinCondition
    ) -> Self {
        addingJoin(joined, kind: .right, on: condition)
    }

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

    public func include<RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>(
        _ relation: KomaToManyRelation<Model.Record, RelatedRecord, RelatedModel>
    ) -> Self where RelatedModel.Record == RelatedRecord {
        var copy = self
        copy.includes.append { records, graphContext in
            try await graphContext.preload(relation, owners: records)
        }
        return copy
    }

    public func include<RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>(
        _ relation: KomaToOneRelation<Model.Record, RelatedRecord, RelatedModel>
    ) -> Self where RelatedModel.Record == RelatedRecord {
        var copy = self
        copy.includes.append { records, graphContext in
            try await graphContext.preload(relation, owners: records)
        }
        return copy
    }

    public func include<RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>(
        _ keyPath: KeyPath<Model, KomaRelationQuery<Model.Record, RelatedRecord, RelatedModel>>
    ) -> Self where RelatedModel.Record == RelatedRecord {
        var copy = self
        copy.includes.append { records, graphContext in
            let models = records.map { Model(record: $0, graphContext: graphContext) }
            guard let relation = models.first?[keyPath: keyPath].relation else {
                return
            }
            try await graphContext.preload(relation, owners: records)
        }
        return copy
    }

    public func include<RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>(
        _ keyPath: KeyPath<Model, KomaToOneRelationQuery<Model.Record, RelatedRecord, RelatedModel>>
    ) -> Self where RelatedModel.Record == RelatedRecord {
        var copy = self
        copy.includes.append { records, graphContext in
            let models = records.map { Model(record: $0, graphContext: graphContext) }
            guard let relation = models.first?[keyPath: keyPath].relation else {
                return
            }
            try await graphContext.preload(relation, owners: records)
        }
        return copy
    }

    public func fetch() async throws -> [Model] {
        let records = try await store.fetch(request)
        let graphContext = KomaGraphContext(store: store)
        for include in includes {
            try await include(records, graphContext)
        }
        return records.map { Model(record: $0, graphContext: graphContext) }
    }

    public func first() async throws -> Model? {
        try await limit(1).fetch().first
    }

    public func count() async throws -> Int {
        try await store.count(request)
    }

    public func exists() async throws -> Bool {
        try await !limit(1).fetch().isEmpty
    }
}

public extension KomaStore {
    func query<Model: KomaModel>(_ model: Model.Type) -> KomaModelQuery<Model> {
        KomaModelQuery(store: self, model: model)
    }
}

private extension KomaModelQuery {
    func addingJoin<Joined: KomaEntityRecord>(
        _ joined: Joined.Type,
        kind: KomaJoinKind,
        on condition: @Sendable (KomaPredicateBuilder<Model.Record>, KomaPredicateBuilder<Joined>) -> KomaJoinCondition
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
