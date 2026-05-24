import Foundation

/// The SQL join strategy used by a Koma query.
public enum KomaJoinKind: String, Sendable {
    case inner
    case left
    case right
}

/// Describes a pair of columns used in a join condition.
public struct KomaJoinColumnPair: Equatable, Sendable {
    public let baseColumn: String
    public let joinedColumn: String

    public init(baseColumn: String, joinedColumn: String) {
        self.baseColumn = baseColumn
        self.joinedColumn = joinedColumn
    }
}

/// A typed join condition built from two record column builders.
public struct KomaJoinCondition: Equatable, Sendable {
    public let columnPairs: [KomaJoinColumnPair]

    public init(columnPairs: [KomaJoinColumnPair]) {
        self.columnPairs = columnPairs
    }
}

/// Describes a joined table used to filter or order a base query.
public struct KomaJoinDescriptor: Sendable {
    public let kind: KomaJoinKind
    public let tableName: String
    public let primaryKey: String
    public let columns: [KomaColumnMetadata]
    public let columnPairs: [KomaJoinColumnPair]

    public init(
        kind: KomaJoinKind,
        tableName: String,
        primaryKey: String,
        columns: [KomaColumnMetadata],
        columnPairs: [KomaJoinColumnPair]
    ) {
        self.kind = kind
        self.tableName = tableName
        self.primaryKey = primaryKey
        self.columns = columns
        self.columnPairs = columnPairs
    }
}

public func == <Value>(lhs: KomaColumnExpression<Value>, rhs: KomaColumnExpression<Value>) -> KomaJoinCondition {
    KomaJoinCondition(columnPairs: [
        KomaJoinColumnPair(baseColumn: lhs.column, joinedColumn: rhs.column)
    ])
}

public func == <Value>(lhs: KomaColumnExpression<Value>, rhs: KomaColumnExpression<Value?>) -> KomaJoinCondition {
    KomaJoinCondition(columnPairs: [
        KomaJoinColumnPair(baseColumn: lhs.column, joinedColumn: rhs.column)
    ])
}

public func == <Value>(lhs: KomaColumnExpression<Value?>, rhs: KomaColumnExpression<Value>) -> KomaJoinCondition {
    KomaJoinCondition(columnPairs: [
        KomaJoinColumnPair(baseColumn: lhs.column, joinedColumn: rhs.column)
    ])
}

public func && (lhs: KomaJoinCondition, rhs: KomaJoinCondition) -> KomaJoinCondition {
    KomaJoinCondition(columnPairs: lhs.columnPairs + rhs.columnPairs)
}
