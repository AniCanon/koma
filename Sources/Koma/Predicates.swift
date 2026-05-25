import Foundation

@dynamicMemberLookup
public struct KomaPredicateBuilder<Record: KomaEntityRecord>: Sendable {
    public init() {}

    public subscript<Value>(dynamicMember keyPath: KeyPath<Record.Columns, KomaColumn<Value>>) -> KomaColumnExpression<Value> {
        let column = Record.columns[keyPath: keyPath]
        return KomaColumnExpression(column: column.name, columnIndex: column.index)
    }
}

public struct KomaColumnExpression<Value>: Sendable {
    public let column: String
    @_documentation(visibility: private)
    public let columnIndex: Int?

    public init(column: String, columnIndex: Int? = nil) {
        self.column = column
        self.columnIndex = columnIndex
    }
}

public struct KomaPredicate: Equatable, Sendable {
    public enum Operation: Equatable, Sendable {
        case isNull
        case isNotNull
        case equals(KomaValue)
        case notEquals(KomaValue)
        case lessThan(KomaValue)
        case lessThanOrEquals(KomaValue)
        case greaterThan(KomaValue)
        case greaterThanOrEquals(KomaValue)
        case like(KomaValue)
        case `in`([KomaValue])
        case between(KomaValue, KomaValue)
        case and([KomaPredicate])
        case or([KomaPredicate])
    }

    public let column: String?
    @_documentation(visibility: private)
    public let columnIndex: Int?
    public let operation: Operation

    public init(column: String?, columnIndex: Int? = nil, operation: Operation) {
        self.column = column
        self.columnIndex = columnIndex
        self.operation = operation
    }

    func qualified(by qualifier: String) -> Self {
        switch operation {
        case .isNull, .isNotNull, .equals, .notEquals, .lessThan, .lessThanOrEquals,
             .greaterThan, .greaterThanOrEquals, .like, .in, .between:
            guard let column, !column.contains(".") else {
                return self
            }
            return KomaPredicate(column: "\(qualifier).\(column)", operation: operation)
        case let .and(predicates):
            return KomaPredicate(column: nil, operation: .and(predicates.map { $0.qualified(by: qualifier) }))
        case let .or(predicates):
            return KomaPredicate(column: nil, operation: .or(predicates.map { $0.qualified(by: qualifier) }))
        }
    }
}

public extension KomaColumnExpression {
    func isNull() -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .isNull)
    }

    func isNotNull() -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .isNotNull)
    }
}

public enum KomaValue: Equatable, Sendable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)

    public var cacheKey: String {
        switch self {
        case let .string(value):
            return "s:\(value)"
        case let .int(value):
            return "i:\(value)"
        case let .double(value):
            return "d:\(value)"
        case let .bool(value):
            return "b:\(value)"
        }
    }
}

public func == <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .equals(rhs.komaValue))
}

public func == <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value?>, rhs: Value?) -> KomaPredicate {
    guard let rhs else {
        return KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .isNull)
    }
    return KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .equals(rhs.komaValue))
}

public func != <Value>(lhs: KomaColumnExpression<Value?>, rhs: Value?) -> KomaPredicate {
    if rhs == nil {
        return KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .isNotNull)
    }
    guard let value = rhs as? any KomaBindableValue else {
        return KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .isNotNull)
    }
    return KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .notEquals(value.komaValue))
}

public func != <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .notEquals(rhs.komaValue))
}

public func < <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .lessThan(rhs.komaValue))
}

public func <= <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .lessThanOrEquals(rhs.komaValue))
}

public func > <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .greaterThan(rhs.komaValue))
}

public func >= <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, columnIndex: lhs.columnIndex, operation: .greaterThanOrEquals(rhs.komaValue))
}

public func && (lhs: KomaPredicate, rhs: KomaPredicate) -> KomaPredicate {
    KomaPredicate(column: nil, operation: .and([lhs, rhs]))
}

public func || (lhs: KomaPredicate, rhs: KomaPredicate) -> KomaPredicate {
    KomaPredicate(column: nil, operation: .or([lhs, rhs]))
}

public protocol KomaBindableValue: Sendable {
    var komaValue: KomaValue { get }
}

extension String: KomaBindableValue {
    public var komaValue: KomaValue {
        .string(self)
    }
}

extension Int: KomaBindableValue {
    public var komaValue: KomaValue {
        .int(Int64(self))
    }
}

extension Int64: KomaBindableValue {
    public var komaValue: KomaValue {
        .int(self)
    }
}

extension Double: KomaBindableValue {
    public var komaValue: KomaValue {
        .double(self)
    }
}

extension Bool: KomaBindableValue {
    public var komaValue: KomaValue {
        .bool(self)
    }
}

extension Date: KomaBindableValue {
    public var komaValue: KomaValue {
        .double(timeIntervalSinceReferenceDate)
    }
}

public extension KomaColumnExpression where Value == String {
    func contains(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .like(.string("%\(value)%")))
    }

    func hasPrefix(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .like(.string("\(value)%")))
    }

    func hasSuffix(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .like(.string("%\(value)")))
    }

    func like(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .like(.string(value)))
    }
}

public extension KomaColumnExpression where Value == String? {
    func contains(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .like(.string("%\(value)%")))
    }

    func hasPrefix(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .like(.string("\(value)%")))
    }

    func hasSuffix(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .like(.string("%\(value)")))
    }

    func like(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .like(.string(value)))
    }
}

public extension KomaColumnExpression where Value: KomaBindableValue {
    func `in`(_ values: [Value]) -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .in(values.map(\.komaValue)))
    }

    func between(_ lowerBound: Value, _ upperBound: Value) -> KomaPredicate {
        KomaPredicate(column: column, columnIndex: columnIndex, operation: .between(lowerBound.komaValue, upperBound.komaValue))
    }
}

public struct KomaSortDescriptor: Equatable, Sendable {
    public let column: String
    @_documentation(visibility: private)
    public let columnIndex: Int?
    public let direction: KomaSortDirection

    public init(column: String, columnIndex: Int? = nil, direction: KomaSortDirection = .ascending) {
        self.column = column
        self.columnIndex = columnIndex
        self.direction = direction
    }
}

public enum KomaSortDirection: String, Equatable, Sendable {
    case ascending = "ASC"
    case descending = "DESC"
}
