import Foundation

enum KomaInMemoryQueryEvaluator {
    static func apply<Record: KomaEntityRecord>(
        _ request: borrowing KomaQueryRequest<Record>,
        to records: [Record]
    ) throws -> [Record] {
        guard request.joins.isEmpty else {
            throw KomaMappingError.unsupportedOutput("Cannot evaluate joined queries in memory.")
        }

        guard Record._komaSQLiteFastPath else {
            return records
        }

        let columns = Dictionary(uniqueKeysWithValues: Record.komaColumns.enumerated().map { ($0.element.name, $0.offset) })
        var projected: [ProjectedRecord<Record>] = []
        projected.reserveCapacity(records.count)

        for record in records {
            var values: [_KomaSQLiteValue] = []
            values.reserveCapacity(Record.komaColumns.count)
            record._komaSQLiteValues(into: &values)
            projected.append(ProjectedRecord(record: record, values: values))
        }

        if let predicate = request.predicate {
            projected = try projected.filter { try Self.matches(predicate, values: $0.values, columns: columns) }
        }

        if !request.order.isEmpty {
            projected.sort { lhs, rhs in
                for descriptor in request.order {
                    guard let index = columns[descriptor.column] else {
                        continue
                    }
                    let comparison = Self.compare(lhs.values[index], rhs.values[index])
                    guard comparison != .orderedSame else {
                        continue
                    }
                    switch descriptor.direction {
                    case .ascending:
                        return comparison == .orderedAscending
                    case .descending:
                        return comparison == .orderedDescending
                    }
                }
                return false
            }
        }

        let offset = min(request.offset ?? 0, projected.count)
        let end: Int = if let limit = request.limit {
            min(offset + limit, projected.count)
        } else {
            projected.count
        }

        return projected[offset ..< end].map(\.record)
    }

    private static func matches(
        _ predicate: KomaPredicate,
        values: borrowing [_KomaSQLiteValue],
        columns: borrowing [String: Int]
    ) throws -> Bool {
        switch predicate.operation {
        case .isNull:
            return try value(for: predicate, values: values, columns: columns) == .null
        case .isNotNull:
            return try value(for: predicate, values: values, columns: columns) != .null
        case let .equals(value):
            return try Self.equals(Self.value(for: predicate, values: values, columns: columns), value)
        case let .notEquals(value):
            return try !Self.equals(Self.value(for: predicate, values: values, columns: columns), value)
        case let .lessThan(value):
            return try Self.compare(Self.value(for: predicate, values: values, columns: columns), value) == .orderedAscending
        case let .lessThanOrEquals(value):
            let comparison = try Self.compare(Self.value(for: predicate, values: values, columns: columns), value)
            return comparison == .orderedAscending || comparison == .orderedSame
        case let .greaterThan(value):
            return try Self.compare(Self.value(for: predicate, values: values, columns: columns), value) == .orderedDescending
        case let .greaterThanOrEquals(value):
            let comparison = try Self.compare(Self.value(for: predicate, values: values, columns: columns), value)
            return comparison == .orderedDescending || comparison == .orderedSame
        case let .like(value):
            guard case let .string(pattern) = value,
                  case let .text(text) = try Self.value(for: predicate, values: values, columns: columns)
            else {
                return false
            }
            return Self.matchesLike(text, pattern: pattern)
        case let .in(expectedValues):
            let stored = try Self.value(for: predicate, values: values, columns: columns)
            return expectedValues.contains { Self.equals(stored, $0) }
        case let .between(lowerBound, upperBound):
            let stored = try Self.value(for: predicate, values: values, columns: columns)
            let lower = Self.compare(stored, lowerBound)
            let upper = Self.compare(stored, upperBound)
            return (lower == .orderedDescending || lower == .orderedSame) &&
                (upper == .orderedAscending || upper == .orderedSame)
        case let .and(predicates):
            for predicate in predicates where try !Self.matches(predicate, values: values, columns: columns) {
                return false
            }
            return true
        case let .or(predicates):
            for predicate in predicates where try Self.matches(predicate, values: values, columns: columns) {
                return true
            }
            return false
        }
    }

    private static func value(
        for predicate: KomaPredicate,
        values: borrowing [_KomaSQLiteValue],
        columns: borrowing [String: Int]
    ) throws -> _KomaSQLiteValue {
        guard let column = predicate.column,
              let index = columns[column],
              values.indices.contains(index)
        else {
            throw KomaMappingError.unsupportedOutput("Cannot evaluate predicate in memory.")
        }
        return values[index]
    }

    private static func equals(_ stored: _KomaSQLiteValue, _ expected: KomaValue) -> Bool {
        compare(stored, expected) == .orderedSame
    }

    private static func compare(_ lhs: _KomaSQLiteValue, _ rhs: KomaValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (.text(lhs), .string(rhs)):
            return lhs.compare(rhs)
        case let (.integer(lhs), .int(rhs)):
            return Self.compare(lhs, rhs)
        case let (.real(lhs), .double(rhs)):
            return Self.compare(lhs, rhs)
        case let (.integer(lhs), .double(rhs)):
            return Self.compare(Double(lhs), rhs)
        case let (.real(lhs), .int(rhs)):
            return Self.compare(lhs, Double(rhs))
        case let (.integer(lhs), .bool(rhs)):
            return (lhs != 0) == rhs ? .orderedSame : (lhs == 0 ? .orderedAscending : .orderedDescending)
        case (.null, _):
            return .orderedAscending
        default:
            return .orderedDescending
        }
    }

    private static func compare(_ lhs: _KomaSQLiteValue, _ rhs: _KomaSQLiteValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.null, .null):
            return .orderedSame
        case (.null, _):
            return .orderedAscending
        case (_, .null):
            return .orderedDescending
        case let (.text(lhs), .text(rhs)):
            return lhs.compare(rhs)
        case let (.integer(lhs), .integer(rhs)):
            return Self.compare(lhs, rhs)
        case let (.real(lhs), .real(rhs)):
            return Self.compare(lhs, rhs)
        case let (.integer(lhs), .real(rhs)):
            return Self.compare(Double(lhs), rhs)
        case let (.real(lhs), .integer(rhs)):
            return Self.compare(lhs, Double(rhs))
        default:
            return .orderedSame
        }
    }

    private static func compare<Value: Comparable>(_ lhs: Value, _ rhs: Value) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }

    private static func matchesLike(_ text: String, pattern: String) -> Bool {
        if pattern.hasPrefix("%"), pattern.hasSuffix("%") {
            return text.contains(pattern.dropFirst().dropLast())
        }
        if pattern.hasPrefix("%") {
            return text.hasSuffix(pattern.dropFirst())
        }
        if pattern.hasSuffix("%") {
            return text.hasPrefix(pattern.dropLast())
        }
        return text == pattern
    }

    private struct ProjectedRecord<Record> {
        let record: Record
        let values: [_KomaSQLiteValue]
    }
}
