import Foundation

@dynamicMemberLookup
public struct KomaPredicateBuilder<Record: KomaEntityRecord>: Sendable {
    public init() {}

    public subscript<Value>(dynamicMember keyPath: KeyPath<Record.Columns, KomaColumn<Value>>) -> KomaColumnExpression<Value> {
        KomaColumnExpression(column: Record.columns[keyPath: keyPath].name)
    }
}

public struct KomaColumnExpression<Value>: Sendable {
    public let column: String

    public init(column: String) {
        self.column = column
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
    public let operation: Operation

    public init(column: String?, operation: Operation) {
        self.column = column
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
        KomaPredicate(column: column, operation: .isNull)
    }

    func isNotNull() -> KomaPredicate {
        KomaPredicate(column: column, operation: .isNotNull)
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
    KomaPredicate(column: lhs.column, operation: .equals(rhs.komaValue))
}

public func == <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value?>, rhs: Value?) -> KomaPredicate {
    guard let rhs else {
        return KomaPredicate(column: lhs.column, operation: .isNull)
    }
    return KomaPredicate(column: lhs.column, operation: .equals(rhs.komaValue))
}

public func != <Value>(lhs: KomaColumnExpression<Value?>, rhs: Value?) -> KomaPredicate {
    if rhs == nil {
        return KomaPredicate(column: lhs.column, operation: .isNotNull)
    }
    guard let value = rhs as? any KomaBindableValue else {
        return KomaPredicate(column: lhs.column, operation: .isNotNull)
    }
    return KomaPredicate(column: lhs.column, operation: .notEquals(value.komaValue))
}

public func != <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, operation: .notEquals(rhs.komaValue))
}

public func < <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, operation: .lessThan(rhs.komaValue))
}

public func <= <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, operation: .lessThanOrEquals(rhs.komaValue))
}

public func > <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, operation: .greaterThan(rhs.komaValue))
}

public func >= <Value: KomaBindableValue>(lhs: KomaColumnExpression<Value>, rhs: Value) -> KomaPredicate {
    KomaPredicate(column: lhs.column, operation: .greaterThanOrEquals(rhs.komaValue))
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
        KomaPredicate(column: column, operation: .like(.string("%\(value)%")))
    }

    func hasPrefix(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, operation: .like(.string("\(value)%")))
    }

    func hasSuffix(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, operation: .like(.string("%\(value)")))
    }

    func like(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, operation: .like(.string(value)))
    }
}

public extension KomaColumnExpression where Value == String? {
    func contains(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, operation: .like(.string("%\(value)%")))
    }

    func hasPrefix(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, operation: .like(.string("\(value)%")))
    }

    func hasSuffix(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, operation: .like(.string("%\(value)")))
    }

    func like(_ value: String) -> KomaPredicate {
        KomaPredicate(column: column, operation: .like(.string(value)))
    }
}

public extension KomaColumnExpression where Value: KomaBindableValue {
    func `in`(_ values: [Value]) -> KomaPredicate {
        KomaPredicate(column: column, operation: .in(values.map(\.komaValue)))
    }

    func between(_ lowerBound: Value, _ upperBound: Value) -> KomaPredicate {
        KomaPredicate(column: column, operation: .between(lowerBound.komaValue, upperBound.komaValue))
    }
}

public struct KomaSortDescriptor: Equatable, Sendable {
    public let column: String
    public let direction: KomaSortDirection

    public init(column: String, direction: KomaSortDirection = .ascending) {
        self.column = column
        self.direction = direction
    }
}

public enum KomaSortDirection: String, Equatable, Sendable {
    case ascending = "ASC"
    case descending = "DESC"
}
