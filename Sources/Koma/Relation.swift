import Foundation

/// Describes a to-many relationship between an owner record and related records.
public struct KomaToManyRelation<Owner: KomaEntityRecord, RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>: Sendable
    where RelatedModel.Record == RelatedRecord
{
    public let name: String
    public let localColumn: String
    public let foreignColumn: String

    public init(name: String, localColumn: String, foreignColumn: String) {
        self.name = name
        self.localColumn = localColumn
        self.foreignColumn = foreignColumn
    }

    func cacheKey(ownerValue: KomaValue) -> String {
        "\(Owner.komaTableName).\(name).\(ownerValue.cacheKey)"
    }
}

/// Marker protocol for macro-expanded or hand-written relation namespaces.
public protocol KomaRelationNamespace: Sendable {}

/// A lazy relationship query.
///
/// Use `fetch()` to execute it, or call the relation directly as shorthand for
/// an unfiltered fetch.
///
/// ```swift
/// let characters = try await project.characters.fetch()
/// let active = try await project.characters
///     .where { $0.deletedAt == nil }
///     .fetch()
/// ```
public struct KomaRelationQuery<Owner: KomaEntityRecord, RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>: Sendable
    where RelatedModel.Record == RelatedRecord
{
    public let relation: KomaToManyRelation<Owner, RelatedRecord, RelatedModel>
    private let graphContext: KomaGraphContext
    private let owner: Owner
    private var request: KomaQueryRequest<RelatedRecord>
    private var isUnmodifiedRelationLoad = true

    public init(
        graphContext: KomaGraphContext,
        owner: Owner,
        relation: KomaToManyRelation<Owner, RelatedRecord, RelatedModel>
    ) {
        self.graphContext = graphContext
        self.owner = owner
        self.relation = relation
        request = KomaQueryRequest(record: RelatedRecord.self)
    }

    public func `where`(_ build: @Sendable (KomaPredicateBuilder<RelatedRecord>) -> KomaPredicate) -> Self {
        var copy = self
        let predicate = build(KomaPredicateBuilder())
        if let existing = copy.request.predicate {
            copy.request.predicate = existing && predicate
        } else {
            copy.request.predicate = predicate
        }
        copy.isUnmodifiedRelationLoad = false
        return copy
    }

    public func order(
        by keyPath: KeyPath<RelatedRecord.Columns, KomaColumn<some Any>>,
        _ direction: KomaSortDirection = .ascending
    ) -> Self {
        var copy = self
        let column = RelatedRecord.columns[keyPath: keyPath]
        copy.request.order.append(
            KomaSortDescriptor(column: column.name, columnIndex: column.index, direction: direction)
        )
        copy.isUnmodifiedRelationLoad = false
        return copy
    }

    public func limit(_ limit: Int) -> Self {
        var copy = self
        copy.request.limit = limit
        copy.isUnmodifiedRelationLoad = false
        return copy
    }

    public func offset(_ offset: Int) -> Self {
        var copy = self
        copy.request.offset = offset
        copy.isUnmodifiedRelationLoad = false
        return copy
    }

    public func fetch() async throws -> [RelatedModel] {
        if isUnmodifiedRelationLoad {
            return try await graphContext.load(relation, owner: owner)
        }
        return try await graphContext.fetch(fetchRequest(), as: RelatedModel.self)
    }

    public func callAsFunction() async throws -> [RelatedModel] {
        try await fetch()
    }

    public func first() async throws -> RelatedModel? {
        try await limit(1).fetch().first
    }

    public func count() async throws -> Int {
        try await graphContext.count(fetchRequest())
    }

    public func exists() async throws -> Bool {
        try await !limit(1).fetch().isEmpty
    }

    private func fetchRequest() throws -> KomaQueryRequest<RelatedRecord> {
        let ownerValue = try KomaRecordValueReader.value(relation.localColumn, in: owner)
        let relationPredicate = KomaPredicate(column: relation.foreignColumn, operation: .equals(ownerValue))
        var request = request
        if let existing = request.predicate {
            request.predicate = relationPredicate && existing
        } else {
            request.predicate = relationPredicate
        }
        return request
    }
}
