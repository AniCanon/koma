import Foundation

/// Describes a to-one relationship between an owner record and a related record.
public struct KomaToOneRelation<Owner: KomaEntityRecord, RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>: Sendable
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

/// A lazy to-one relationship query.
public struct KomaToOneRelationQuery<Owner: KomaEntityRecord, RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>: Sendable
    where RelatedModel.Record == RelatedRecord
{
    public let relation: KomaToOneRelation<Owner, RelatedRecord, RelatedModel>
    private let graphContext: KomaGraphContext
    private let owner: Owner
    private var request: KomaQueryRequest<RelatedRecord>
    private var isUnmodifiedRelationLoad = true

    public init(
        graphContext: KomaGraphContext,
        owner: Owner,
        relation: KomaToOneRelation<Owner, RelatedRecord, RelatedModel>
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
        let column = RelatedRecord.columns[keyPath: keyPath].name
        copy.request.order.append(KomaSortDescriptor(column: column, direction: direction))
        copy.isUnmodifiedRelationLoad = false
        return copy
    }

    public func fetch() async throws -> RelatedModel? {
        if isUnmodifiedRelationLoad {
            return try await graphContext.load(relation, owner: owner)
        }
        var request = try fetchRequest()
        request.limit = request.limit ?? 1
        return try await graphContext.fetch(request, as: RelatedModel.self).first
    }

    public func callAsFunction() async throws -> RelatedModel? {
        try await fetch()
    }

    public func count() async throws -> Int {
        try await graphContext.count(fetchRequest())
    }

    public func exists() async throws -> Bool {
        try await fetch() != nil
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
