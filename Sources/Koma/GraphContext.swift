import Foundation

/// Holds memoized relationship data for a set of hydrated models.
///
/// Koma creates a graph context for each model query. Lazy relationship access
/// and `.include(...)` share the same context, so repeated reads avoid duplicate
/// SQLite work.
public actor KomaGraphContext {
    private let store: any KomaStore
    private var toManyCache: [String: any Sendable] = [:]
    private var toOneCache: [String: any Sendable] = [:]

    public init(store: any KomaStore) {
        self.store = store
    }

    public func load<Owner: KomaEntityRecord, RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>(
        _ relation: KomaToManyRelation<Owner, RelatedRecord, RelatedModel>,
        owner: Owner
    ) async throws -> [RelatedModel] where RelatedModel.Record == RelatedRecord {
        let ownerValue = try KomaRecordValueReader.value(relation.localColumn, in: owner)
        let cacheKey = relation.cacheKey(ownerValue: ownerValue)
        if let cached = toManyCache[cacheKey] as? [RelatedModel] {
            return cached
        }

        let request = KomaQueryRequest(
            record: RelatedRecord.self,
            predicate: KomaPredicate(column: relation.foreignColumn, operation: .equals(ownerValue))
        )
        let records = try await store.fetch(request)
        let models = records.map { RelatedModel(record: $0, graphContext: self) }
        toManyCache[cacheKey] = models
        return models
    }

    public func preload<Owner: KomaEntityRecord, RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>(
        _ relation: KomaToManyRelation<Owner, RelatedRecord, RelatedModel>,
        owners: [Owner]
    ) async throws where RelatedModel.Record == RelatedRecord {
        let ownerValues = try owners.map { try KomaRecordValueReader.value(relation.localColumn, in: $0) }
        let uncachedValues = ownerValues.filter { self.toManyCache[relation.cacheKey(ownerValue: $0)] == nil }
        guard !uncachedValues.isEmpty else {
            return
        }

        let request = KomaQueryRequest(
            record: RelatedRecord.self,
            predicate: KomaPredicate(column: relation.foreignColumn, operation: .in(uncachedValues))
        )
        let records = try await store.fetch(request)
        let grouped = try Dictionary(grouping: records) { record in
            try KomaRecordValueReader.value(relation.foreignColumn, in: record).cacheKey
        }

        for ownerValue in ownerValues {
            let relatedRecords = grouped[ownerValue.cacheKey] ?? []
            toManyCache[relation.cacheKey(ownerValue: ownerValue)] = relatedRecords.map {
                RelatedModel(record: $0, graphContext: self)
            }
        }
    }

    public func load<Owner: KomaEntityRecord, RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>(
        _ relation: KomaToOneRelation<Owner, RelatedRecord, RelatedModel>,
        owner: Owner
    ) async throws -> RelatedModel? where RelatedModel.Record == RelatedRecord {
        let ownerValue = try KomaRecordValueReader.value(relation.localColumn, in: owner)
        let cacheKey = relation.cacheKey(ownerValue: ownerValue)
        if let cached = toOneCache[cacheKey] as? KomaOptionalCacheValue<RelatedModel> {
            return cached.value
        }

        let request = KomaQueryRequest(
            record: RelatedRecord.self,
            predicate: KomaPredicate(column: relation.foreignColumn, operation: .equals(ownerValue)),
            limit: 1
        )
        let record = try await store.fetch(request).first
        let model = record.map { RelatedModel(record: $0, graphContext: self) }
        toOneCache[cacheKey] = KomaOptionalCacheValue(value: model)
        return model
    }

    public func preload<Owner: KomaEntityRecord, RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>(
        _ relation: KomaToOneRelation<Owner, RelatedRecord, RelatedModel>,
        owners: [Owner]
    ) async throws where RelatedModel.Record == RelatedRecord {
        let ownerValues = try owners.map { try KomaRecordValueReader.value(relation.localColumn, in: $0) }
        let uncachedValues = ownerValues.filter { self.toOneCache[relation.cacheKey(ownerValue: $0)] == nil }
        guard !uncachedValues.isEmpty else {
            return
        }

        let request = KomaQueryRequest(
            record: RelatedRecord.self,
            predicate: KomaPredicate(column: relation.foreignColumn, operation: .in(uncachedValues))
        )
        let records = try await store.fetch(request)
        var firstByOwnerValue: [String: RelatedRecord] = [:]
        for record in records {
            let ownerValue = try KomaRecordValueReader.value(relation.foreignColumn, in: record)
            firstByOwnerValue[ownerValue.cacheKey] = firstByOwnerValue[ownerValue.cacheKey] ?? record
        }

        for ownerValue in ownerValues {
            let record = firstByOwnerValue[ownerValue.cacheKey]
            let model = record.map { RelatedModel(record: $0, graphContext: self) }
            toOneCache[relation.cacheKey(ownerValue: ownerValue)] = KomaOptionalCacheValue(value: model)
        }
    }

    public func fetch<Record: KomaEntityRecord, Model: KomaModel>(
        _ request: KomaQueryRequest<Record>,
        as model: Model.Type = Model.self
    ) async throws -> [Model] where Model.Record == Record {
        let records = try await store.fetch(request)
        return records.map { Model(record: $0, graphContext: self) }
    }

    public func count(_ request: KomaQueryRequest<some KomaEntityRecord>) async throws -> Int {
        try await store.count(request)
    }
}

private struct KomaOptionalCacheValue<Value: Sendable> {
    let value: Value?
}
