import Foundation
import Koma

extension SQLiteKomaStore {
    static func columnNames(from columns: [KomaColumnMetadata]) -> [String] {
        var names: [String] = []
        names.reserveCapacity(columns.count)
        for column in columns {
            names.append(column.name)
        }
        return names
    }

    static func quotedColumnList(_ columns: [KomaColumnMetadata]) -> String {
        var sql = ""
        sql.reserveCapacity(columns.count * 12)
        for (index, column) in columns.enumerated() {
            if index > 0 {
                sql.append(", ")
            }
            Self.appendQuotedIdentifier(column.name, to: &sql)
        }
        return sql
    }

    static func quotedColumnList(_ columns: [String]) -> String {
        var sql = ""
        sql.reserveCapacity(columns.count * 12)
        for (index, column) in columns.enumerated() {
            if index > 0 {
                sql.append(", ")
            }
            Self.appendQuotedIdentifier(column, to: &sql)
        }
        return sql
    }

    static func quotedSelectColumnList(_ columns: [KomaColumnMetadata], qualifier: String?) -> String {
        var sql = ""
        sql.reserveCapacity(columns.count * 20)
        for (index, column) in columns.enumerated() {
            if index > 0 {
                sql.append(", ")
            }
            Self.appendColumnReference(column.name, defaultQualifier: qualifier, to: &sql)
        }
        return sql
    }

    static func placeholders(count: Int) -> String {
        guard count > 0 else {
            return ""
        }

        var sql = "?"
        sql.reserveCapacity(max(1, count) * 3)
        for _ in 1 ..< count {
            sql.append(", ?")
        }
        return sql
    }

    static func upsertAssignments(columns: [KomaColumnMetadata], primaryKey: String) -> String {
        var sql = ""
        for column in columns where column.name != primaryKey {
            if !sql.isEmpty {
                sql.append(", ")
            }
            Self.appendQuotedIdentifier(column.name, to: &sql)
            sql.append(" = excluded.")
            Self.appendQuotedIdentifier(column.name, to: &sql)
        }
        return sql
    }

    /// `IS NOT` comparisons (NULL-safe) over the non-key columns, used to skip conflicting
    /// rows whose values are already identical: unchanged rows dirty no pages, fire no
    /// triggers, and stay out of `sqlite3_total_changes`, so a no-change refresh is a no-op
    /// for the WAL, the disk, and live observers.
    static func upsertChangeGuard(columns: [KomaColumnMetadata], primaryKey: String) -> String {
        var sql = ""
        for column in columns where column.name != primaryKey {
            if !sql.isEmpty {
                sql.append(" OR ")
            }
            Self.appendQuotedIdentifier(column.name, to: &sql)
            sql.append(" IS NOT excluded.")
            Self.appendQuotedIdentifier(column.name, to: &sql)
        }
        return sql
    }

    static func upsertSQL(tableName: String, primaryKey: String, columns: [KomaColumnMetadata]) -> String {
        let columnList = Self.quotedColumnList(columns)
        let placeholders = Self.placeholders(count: columns.count)
        let updates = Self.upsertAssignments(columns: columns, primaryKey: primaryKey)
        let changeGuard = Self.upsertChangeGuard(columns: columns, primaryKey: primaryKey)

        var sql = "INSERT INTO "
        sql.reserveCapacity(
            tableName.utf8.count + columnList.utf8.count + placeholders.utf8.count
                + updates.utf8.count + changeGuard.utf8.count + 112
        )
        Self.appendQuotedIdentifier(tableName, to: &sql)
        sql.append(" (")
        sql.append(columnList)
        sql.append(") VALUES (")
        sql.append(placeholders)
        sql.append(")")

        sql.append(" ON CONFLICT(")
        Self.appendQuotedIdentifier(primaryKey, to: &sql)

        guard !updates.isEmpty else {
            // Key-only table: re-upserting an existing key is a no-op, not a constraint error.
            sql.append(") DO NOTHING")
            return sql
        }

        sql.append(") DO UPDATE SET ")
        sql.append(updates)
        sql.append(" WHERE ")
        sql.append(changeGuard)
        return sql
    }

    static func selectSQL(tableName: String, columns: [KomaColumnMetadata], joins: [KomaJoinDescriptor] = []) -> String {
        let qualifier = joins.isEmpty ? nil : tableName
        let columnList = Self.quotedSelectColumnList(columns, qualifier: qualifier)
        var sql = "SELECT "
        sql.reserveCapacity(tableName.utf8.count + columnList.utf8.count + joins.count * 64 + 32)
        if !joins.isEmpty {
            sql.append("DISTINCT ")
        }
        sql.append(columnList)
        sql.append(" FROM ")
        Self.appendQuotedIdentifier(tableName, to: &sql)
        Self.appendJoins(joins, baseTableName: tableName, to: &sql)
        return sql
    }

    static func countSQL(tableName: String) -> String {
        var sql = "SELECT COUNT(*) FROM "
        sql.reserveCapacity(tableName.utf8.count + 23)
        Self.appendQuotedIdentifier(tableName, to: &sql)
        return sql
    }

    static func countSQL(tableName: String, primaryKey: String, joins: [KomaJoinDescriptor]) -> String {
        guard !joins.isEmpty else {
            return countSQL(tableName: tableName)
        }

        var sql = "SELECT COUNT(DISTINCT "
        sql.reserveCapacity(tableName.utf8.count + primaryKey.utf8.count + joins.count * 64 + 48)
        Self.appendColumnReference(primaryKey, defaultQualifier: tableName, to: &sql)
        sql.append(") FROM ")
        Self.appendQuotedIdentifier(tableName, to: &sql)
        Self.appendJoins(joins, baseTableName: tableName, to: &sql)
        return sql
    }

    static func updateAssignments(_ assignments: [KomaUpdateAssignment]) -> String {
        var sql = ""
        sql.reserveCapacity(assignments.count * 16)
        for (index, assignment) in assignments.enumerated() {
            if index > 0 {
                sql.append(", ")
            }
            Self.appendQuotedIdentifier(assignment.column, to: &sql)
            sql.append(" = ?")
        }
        return sql
    }

    static func orderClause(_ descriptors: [KomaSortDescriptor], defaultQualifier: String? = nil) -> String {
        var sql = ""
        sql.reserveCapacity(descriptors.count * 16)
        for (index, descriptor) in descriptors.enumerated() {
            if index > 0 {
                sql.append(", ")
            }
            Self.appendColumnReference(descriptor.column, defaultQualifier: defaultQualifier, to: &sql)
            sql.append(" ")
            sql.append(descriptor.direction.rawValue)
        }
        return sql
    }

    static func columnPredicate(_ column: String, suffix: String, defaultQualifier: String? = nil) -> String {
        var sql = ""
        sql.reserveCapacity(column.utf8.count + suffix.utf8.count + 12)
        Self.appendColumnReference(column, defaultQualifier: defaultQualifier, to: &sql)
        sql.append(suffix)
        return sql
    }

    static func inPredicate(column: String, placeholders: String, defaultQualifier: String? = nil) -> String {
        var sql = ""
        sql.reserveCapacity(column.utf8.count + placeholders.utf8.count + 16)
        Self.appendColumnReference(column, defaultQualifier: defaultQualifier, to: &sql)
        sql.append(" IN (")
        sql.append(placeholders)
        sql.append(")")
        return sql
    }

    static func appendColumnReference(_ column: String, defaultQualifier: String?, to sql: inout String) {
        if let dotIndex = column.firstIndex(of: ".") {
            let qualifier = String(column[..<dotIndex])
            let columnName = String(column[column.index(after: dotIndex)...])
            Self.appendQuotedIdentifier(qualifier, to: &sql)
            sql.append(".")
            Self.appendQuotedIdentifier(columnName, to: &sql)
            return
        }

        if let defaultQualifier {
            Self.appendQuotedIdentifier(defaultQualifier, to: &sql)
            sql.append(".")
        }
        Self.appendQuotedIdentifier(column, to: &sql)
    }

    private static func appendJoins(_ joins: [KomaJoinDescriptor], baseTableName: String, to sql: inout String) {
        for join in joins {
            switch join.kind {
            case .inner:
                sql.append(" INNER JOIN ")
            case .left:
                sql.append(" LEFT JOIN ")
            case .right:
                sql.append(" RIGHT JOIN ")
            }
            appendQuotedIdentifier(join.tableName, to: &sql)
            sql.append(" ON ")
            for (index, pair) in join.columnPairs.enumerated() {
                if index > 0 {
                    sql.append(" AND ")
                }
                appendColumnReference(pair.baseColumn, defaultQualifier: baseTableName, to: &sql)
                sql.append(" = ")
                appendColumnReference(pair.joinedColumn, defaultQualifier: join.tableName, to: &sql)
            }
        }
    }
}
