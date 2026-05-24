import Foundation

/// An app-facing model hydrated from a normalized record and graph context.
///
/// Use `@KomaModel` on a struct to generate this conformance from a stored
/// record type.
///
/// ```swift
/// @KomaModel(record: ProjectRecord.self)
/// struct ProjectModel {
///     var id: String
///     var name: String
/// }
/// ```
public protocol KomaModel: Sendable {
    associatedtype Record: KomaEntityRecord

    init(record: Record, graphContext: KomaGraphContext)

    var komaRecord: Record { get }
    var komaGraphContext: KomaGraphContext { get }
}

public extension KomaModel {
    /// Creates a lazy relationship query for a relation declared on this model.
    func relation<RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>(
        _ relation: KomaToManyRelation<Record, RelatedRecord, RelatedModel>
    ) -> KomaRelationQuery<Record, RelatedRecord, RelatedModel> where RelatedModel.Record == RelatedRecord {
        KomaRelationQuery(
            graphContext: komaGraphContext,
            owner: komaRecord,
            relation: relation
        )
    }

    /// Creates a lazy to-one relationship query for a relation declared on this model.
    func relation<RelatedRecord: KomaEntityRecord, RelatedModel: KomaModel>(
        _ relation: KomaToOneRelation<Record, RelatedRecord, RelatedModel>
    ) -> KomaToOneRelationQuery<Record, RelatedRecord, RelatedModel> where RelatedModel.Record == RelatedRecord {
        KomaToOneRelationQuery(
            graphContext: komaGraphContext,
            owner: komaRecord,
            relation: relation
        )
    }
}
