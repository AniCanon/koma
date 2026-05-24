import Foundation
import Koma

extension SQLiteKomaStore {
    static func render(
        _ predicate: KomaPredicate,
        defaultQualifier: String? = nil
    ) throws -> (sql: String, arguments: [KomaValue]) {
        switch predicate.operation {
        case .isNull:
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            return (Self.columnPredicate(column, suffix: " IS NULL", defaultQualifier: defaultQualifier), [])
        case .isNotNull:
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            return (Self.columnPredicate(column, suffix: " IS NOT NULL", defaultQualifier: defaultQualifier), [])
        case let .equals(value):
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            return (Self.columnPredicate(column, suffix: " = ?", defaultQualifier: defaultQualifier), [value])
        case let .notEquals(value):
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            return (Self.columnPredicate(column, suffix: " != ?", defaultQualifier: defaultQualifier), [value])
        case let .lessThan(value):
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            return (Self.columnPredicate(column, suffix: " < ?", defaultQualifier: defaultQualifier), [value])
        case let .lessThanOrEquals(value):
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            return (Self.columnPredicate(column, suffix: " <= ?", defaultQualifier: defaultQualifier), [value])
        case let .greaterThan(value):
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            return (Self.columnPredicate(column, suffix: " > ?", defaultQualifier: defaultQualifier), [value])
        case let .greaterThanOrEquals(value):
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            return (Self.columnPredicate(column, suffix: " >= ?", defaultQualifier: defaultQualifier), [value])
        case let .like(value):
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            return (Self.columnPredicate(column, suffix: " LIKE ?", defaultQualifier: defaultQualifier), [value])
        case let .in(values):
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            guard !values.isEmpty else { return ("0", []) }
            let placeholders = Self.placeholders(count: values.count)
            return (Self.inPredicate(column: column, placeholders: placeholders, defaultQualifier: defaultQualifier), values)
        case let .between(lowerBound, upperBound):
            guard let column = predicate.column else { throw SQLiteKomaError.invalidPredicate }
            return (Self.columnPredicate(column, suffix: " BETWEEN ? AND ?", defaultQualifier: defaultQualifier), [
                lowerBound,
                upperBound
            ])
        case let .and(predicates):
            return try Self.renderCompound(predicates, separator: " AND ", defaultQualifier: defaultQualifier)
        case let .or(predicates):
            return try Self.renderCompound(predicates, separator: " OR ", defaultQualifier: defaultQualifier)
        }
    }

    private static func renderCompound(
        _ predicates: [KomaPredicate],
        separator: String,
        defaultQualifier: String?
    ) throws -> (sql: String, arguments: [KomaValue]) {
        var sql = ""
        var arguments: [KomaValue] = []

        for (index, predicate) in predicates.enumerated() {
            let rendered = try Self.render(predicate, defaultQualifier: defaultQualifier)
            if index > 0 {
                sql.append(separator)
            }
            sql.append("(")
            sql.append(rendered.sql)
            sql.append(")")
            arguments.append(contentsOf: rendered.arguments)
        }

        return (sql, arguments)
    }
}
