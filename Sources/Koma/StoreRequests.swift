import Foundation

public struct KomaQueryRequest<Record: KomaEntityRecord>: Sendable {
    public let record: Record.Type
    public var predicate: KomaPredicate?
    public var order: [KomaSortDescriptor]
    public var limit: Int?
    public var offset: Int?
    public var joins: [KomaJoinDescriptor]

    public init(
        record: Record.Type,
        predicate: KomaPredicate? = nil,
        order: [KomaSortDescriptor] = [],
        limit: Int? = nil,
        offset: Int? = nil,
        joins: [KomaJoinDescriptor] = []
    ) {
        self.record = record
        self.predicate = predicate
        self.order = order
        self.limit = limit
        self.offset = offset
        self.joins = joins
    }
}

public struct KomaDeleteRequest<Record: KomaEntityRecord>: Sendable {
    public let record: Record.Type
    public var predicate: KomaPredicate?

    public init(record: Record.Type, predicate: KomaPredicate? = nil) {
        self.record = record
        self.predicate = predicate
    }
}

public struct KomaUpdateAssignment: Equatable, Sendable {
    public let column: String
    public let value: KomaValue?

    public init(column: String, value: KomaValue?) {
        self.column = column
        self.value = value
    }
}

public struct KomaUpdateRequest<Record: KomaEntityRecord>: Sendable {
    public let record: Record.Type
    public var assignments: [KomaUpdateAssignment]
    public var predicate: KomaPredicate?

    public init(
        record: Record.Type,
        assignments: [KomaUpdateAssignment] = [],
        predicate: KomaPredicate? = nil
    ) {
        self.record = record
        self.assignments = assignments
        self.predicate = predicate
    }
}
