import Foundation

enum KomaInMemoryQueryEvaluator {
    static func apply<Record: KomaEntityRecord>(
        _ request: borrowing KomaQueryRequest<Record>,
        to records: [Record]
    ) throws -> [Record] {
        guard request.joins.isEmpty else {
            throw KomaMappingError.unsupportedOutput("Cannot evaluate joined queries in memory.")
        }

        guard Record.self is any KomaSQLiteFastPathRecord.Type else {
            return records
        }

        let projectedColumns = try projectedColumns(for: request)

        if projectedColumns.sourceIndexes.isEmpty,
           request.predicate == nil,
           request.order.isEmpty
        {
            return Array(page(records, offset: request.offset, limit: request.limit))
        }

        var projected: [KomaProjectedRecord<Record>] = []
        projected.reserveCapacity(records.count)

        for record in records {
            let values: KomaProjectedValues
            if projectedColumns.sourceIndexes.isEmpty {
                values = KomaProjectedValues()
            } else {
                guard let fastRecord = record as? any KomaSQLiteFastPathRecord else {
                    return records
                }
                values = KomaProjectedValues(sourceIndexes: projectedColumns.sourceIndexes, record: fastRecord)
            }
            projected.append(
                KomaProjectedRecord(
                    record: record,
                    values: values
                )
            )
        }

        if let predicate = request.predicate {
            projected = try projected.filter { try Self.matches(predicate, values: $0.values, columns: projectedColumns) }
        }

        if !request.order.isEmpty {
            projected.sort { lhs, rhs in
                for descriptor in request.order {
                    guard let index = projectedColumns.projectedIndex(for: descriptor) else {
                        continue
                    }
                    guard let lhsValue = lhs.values.value(at: index),
                          let rhsValue = rhs.values.value(at: index)
                    else {
                        continue
                    }
                    let comparison = Self.compare(lhsValue, rhsValue)
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

    private static func page<Record>(
        _ records: borrowing [Record],
        offset requestedOffset: Int?,
        limit requestedLimit: Int?
    ) -> ArraySlice<Record> {
        let offset = min(requestedOffset ?? 0, records.count)
        let end: Int = if let requestedLimit {
            min(offset + requestedLimit, records.count)
        } else {
            records.count
        }
        return records[offset ..< end]
    }

    private static func projectedColumns<Record: KomaEntityRecord>(
        for request: borrowing KomaQueryRequest<Record>
    ) throws -> KomaProjectedColumns {
        var projectedColumns = KomaProjectedColumns()
        var columnsByName: [String: Int]?

        if let predicate = request.predicate {
            try collectColumns(
                from: predicate,
                record: Record.self,
                projectedColumns: &projectedColumns,
                columnsByName: &columnsByName
            )
        }
        for descriptor in request.order {
            try projectedColumns.append(
                column: descriptor.column,
                columnIndex: descriptor.columnIndex,
                record: Record.self,
                columnsByName: &columnsByName
            )
        }
        return projectedColumns
    }

    private static func collectColumns(
        from predicate: KomaPredicate,
        record: (some KomaEntityRecord).Type,
        projectedColumns: inout KomaProjectedColumns,
        columnsByName: inout [String: Int]?
    ) throws {
        if predicate.column != nil || predicate.columnIndex != nil {
            try projectedColumns.append(
                column: predicate.column,
                columnIndex: predicate.columnIndex,
                record: record,
                columnsByName: &columnsByName
            )
        }

        switch predicate.operation {
        case let .and(predicates), let .or(predicates):
            for predicate in predicates {
                try collectColumns(
                    from: predicate,
                    record: record,
                    projectedColumns: &projectedColumns,
                    columnsByName: &columnsByName
                )
            }
        default:
            break
        }
    }

    private static func matches(
        _ predicate: KomaPredicate,
        values: borrowing KomaProjectedValues,
        columns: borrowing KomaProjectedColumns
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
        values: borrowing KomaProjectedValues,
        columns: borrowing KomaProjectedColumns
    ) throws -> KomaSQLiteStorageValue {
        guard let index = columns.projectedIndex(for: predicate),
              let value = values.value(at: index)
        else {
            throw KomaMappingError.unsupportedOutput("Cannot evaluate predicate in memory.")
        }
        return value
    }

    private static func equals(_ stored: KomaSQLiteStorageValue, _ expected: KomaValue) -> Bool {
        compare(stored, expected) == .orderedSame
    }

    private static func compare(_ lhs: KomaSQLiteStorageValue, _ rhs: KomaValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (.text(lhs), .string(rhs)):
            return compareText(lhs, rhs)
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

    private static func compare(_ lhs: KomaSQLiteStorageValue, _ rhs: KomaSQLiteStorageValue) -> ComparisonResult {
        switch (lhs, rhs) {
        case (.null, .null):
            return .orderedSame
        case (.null, _):
            return .orderedAscending
        case (_, .null):
            return .orderedDescending
        case let (.text(lhs), .text(rhs)):
            return compareText(lhs, rhs)
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

    private static func compareText(_ lhs: String, _ rhs: String) -> ComparisonResult {
        var lhs = lhs
        var rhs = rhs
        return lhs.withUTF8 { lhsBytes in
            rhs.withUTF8 { rhsBytes in
                let count = min(lhsBytes.count, rhsBytes.count)
                for index in 0 ..< count {
                    let left = lhsBytes[index]
                    let right = rhsBytes[index]
                    if left < right {
                        return .orderedAscending
                    }
                    if left > right {
                        return .orderedDescending
                    }
                }

                return compare(lhsBytes.count, rhsBytes.count)
            }
        }
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
}

private struct KomaProjectedRecord<Record> {
    let record: Record
    let values: KomaProjectedValues
}

private struct KomaProjectedValues {
    private let first: KomaSQLiteStorageValue
    private let second: KomaSQLiteStorageValue
    private let remaining: [KomaSQLiteStorageValue]

    init() {
        first = .null
        second = .null
        remaining = []
    }

    init(sourceIndexes: borrowing[Int], record: any KomaSQLiteFastPathRecord) {
        first = sourceIndexes.indices.contains(0) ? record.komaSQLiteValue(at: sourceIndexes[0]) : .null
        second = sourceIndexes.indices.contains(1) ? record.komaSQLiteValue(at: sourceIndexes[1]) : .null

        guard sourceIndexes.count > 2 else {
            remaining = []
            return
        }

        var remaining: [KomaSQLiteStorageValue] = []
        remaining.reserveCapacity(sourceIndexes.count - 2)
        for index in 2 ..< sourceIndexes.count {
            remaining.append(record.komaSQLiteValue(at: sourceIndexes[index]))
        }
        self.remaining = remaining
    }

    func value(at index: Int) -> KomaSQLiteStorageValue? {
        switch index {
        case 0:
            first
        case 1:
            second
        default:
            remaining.indices.contains(index - 2) ? remaining[index - 2] : nil
        }
    }
}

private struct KomaProjectedColumns {
    var sourceIndexes: [Int] = []
    private var names: [String?] = []

    mutating func append(
        column: String?,
        columnIndex: Int?,
        record: (some KomaEntityRecord).Type,
        columnsByName: inout [String: Int]?
    ) throws {
        let sourceIndex: Int
        if let columnIndex {
            sourceIndex = columnIndex
        } else if let column {
            sourceIndex = try Self.columnIndex(column, record: record, columnsByName: &columnsByName)
        } else {
            return
        }

        if let projectedIndex = sourceIndexes.firstIndex(of: sourceIndex) {
            if names[projectedIndex] == nil, let column {
                names[projectedIndex] = column
            }
            return
        }

        sourceIndexes.append(sourceIndex)
        names.append(column)
    }

    func projectedIndex(for predicate: KomaPredicate) -> Int? {
        if let sourceIndex = predicate.columnIndex,
           let projectedIndex = sourceIndexes.firstIndex(of: sourceIndex)
        {
            return projectedIndex
        }

        guard let column = predicate.column else {
            return nil
        }
        return names.firstIndex { $0 == column }
    }

    func projectedIndex(for descriptor: KomaSortDescriptor) -> Int? {
        if let sourceIndex = descriptor.columnIndex,
           let projectedIndex = sourceIndexes.firstIndex(of: sourceIndex)
        {
            return projectedIndex
        }
        return names.firstIndex { $0 == descriptor.column }
    }

    private static func columnIndex<Record: KomaEntityRecord>(
        _ column: String,
        record: Record.Type,
        columnsByName: inout [String: Int]?
    ) throws -> Int {
        if columnsByName == nil {
            columnsByName = Dictionary(
                uniqueKeysWithValues: Record.komaColumns.enumerated().map { ($0.element.name, $0.offset) }
            )
        }
        guard let index = columnsByName?[column] else {
            throw KomaMappingError.unsupportedOutput("Cannot evaluate query column \(column) in memory.")
        }
        return index
    }
}
