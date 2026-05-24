import CKomaSQLite
import Foundation
import Koma

extension SQLiteKomaStore {
    func ensureSchema(for entities: [any KomaEntityRecord.Type]) throws {
        guard canUseFreshSchemaCreation else {
            for entity in entities {
                try ensureSchema(
                    tableName: entity.komaTableName,
                    primaryKey: entity.komaPrimaryKey,
                    columns: entity.komaColumns,
                    generatedSQL: (entity as? any KomaGeneratedSchemaRecord.Type)?.komaGeneratedCreateTableSQL
                )
            }
            return
        }

        var sql = ""
        var tableNames: [String] = []
        for entity in entities where !ensuredTables.contains(entity.komaTableName) {
            if !sql.isEmpty {
                sql.append("; ")
            }
            appendCreateTableSQL(
                tableName: entity.komaTableName,
                columns: entity.komaColumns,
                generatedSQL: (entity as? any KomaGeneratedSchemaRecord.Type)?.komaGeneratedCreateTableSQL,
                to: &sql
            )
            tableNames.append(entity.komaTableName)
        }

        guard !sql.isEmpty else {
            return
        }

        try execute(sql)
        ensuredTables.formUnion(tableNames)
    }

    func ensureSchema(
        tableName: String,
        primaryKey: String,
        columns: [KomaColumnMetadata],
        generatedSQL: String? = nil
    ) throws {
        guard !ensuredTables.contains(tableName) else {
            return
        }

        if canUseFreshSchemaCreation {
            try createTable(tableName: tableName, columns: columns, generatedSQL: generatedSQL)
            ensuredTables.insert(tableName)
            return
        }

        if try !tableExists(tableName) {
            try createTable(tableName: tableName, columns: columns, generatedSQL: generatedSQL)
            ensuredTables.insert(tableName)
            return
        }

        try reconcileSchema(tableName: tableName, primaryKey: primaryKey, columns: columns)
        ensuredTables.insert(tableName)
    }

    func createTable(tableName: String, columns: [KomaColumnMetadata], generatedSQL: String? = nil) throws {
        var sql = ""
        appendCreateTableSQL(tableName: tableName, columns: columns, generatedSQL: generatedSQL, to: &sql)
        try execute(sql)
    }

    private func appendCreateTableSQL(
        tableName: String,
        columns: [KomaColumnMetadata],
        generatedSQL: String?,
        to sql: inout String
    ) {
        if let generatedSQL {
            sql.append(generatedSQL)
            return
        }

        sql.append("CREATE TABLE IF NOT EXISTS ")
        Self.appendQuotedIdentifier(tableName, to: &sql)
        sql.append(" (")

        var definitions = ""
        for column in columns {
            if !definitions.isEmpty {
                definitions.append(", ")
            }
            Self.appendQuotedIdentifier(column.name, to: &definitions)
            definitions.append(" ")
            definitions.append(column.storage.sqliteType)
            if column.isPrimaryKey {
                definitions.append(" PRIMARY KEY NOT NULL")
            }
        }
        sql.append(definitions)
        sql.append(")")
    }

    private func reconcileSchema(tableName: String, primaryKey: String, columns: [KomaColumnMetadata]) throws {
        let existingColumns = try tableColumns(tableName)

        if let existingPrimaryKey = existingColumns.values.first(where: \.isPrimaryKey),
           existingPrimaryKey.name != primaryKey
        {
            throw SQLiteKomaError.incompatibleSchema(
                "Table \(tableName) has primary key \(existingPrimaryKey.name), expected \(primaryKey)."
            )
        }

        for column in columns {
            guard let existing = existingColumns[column.name] else {
                guard !column.isPrimaryKey else {
                    throw SQLiteKomaError.incompatibleSchema("Table \(tableName) is missing primary key \(column.name).")
                }
                let sql = "ALTER TABLE \(Self.quote(tableName)) ADD COLUMN \(Self.quote(column.name)) \(column.storage.sqliteType)"
                try execute(sql)
                continue
            }

            guard Self.storage(column.storage, matchesSQLiteType: existing.type) else {
                throw SQLiteKomaError.incompatibleSchema(
                    "Table \(tableName) column \(column.name) is \(existing.type), expected \(column.storage.sqliteType)."
                )
            }
        }
    }

    private func tableExists(_ tableName: String) throws -> Bool {
        try withStatement("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1") { statement in
            sqlite3_bind_text(statement, 1, tableName, -1, SQLITE_TRANSIENT)
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                return true
            }
            guard step == SQLITE_DONE else {
                throw SQLiteKomaError.executionFailed("Unable to inspect SQLite schema.")
            }
            return false
        }
    }

    private func tableColumns(_ tableName: String) throws -> [String: SQLiteColumnInfo] {
        try withStatement("PRAGMA table_info(\(Self.quote(tableName)))") { statement in
            var columns: [String: SQLiteColumnInfo] = [:]
            while true {
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE {
                    break
                }
                guard step == SQLITE_ROW else {
                    throw SQLiteKomaError.executionFailed("Unable to inspect SQLite table columns.")
                }

                let name = sqlite3_column_text(statement, 1).map { String(cString: $0) } ?? ""
                let type = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                columns[name] = SQLiteColumnInfo(
                    name: name,
                    type: type,
                    isPrimaryKey: sqlite3_column_int(statement, 5) != 0
                )
            }
            return columns
        }
    }

    private static func storage(_ storage: KomaStorageKind, matchesSQLiteType type: String) -> Bool {
        let normalized = type.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        switch storage {
        case .text:
            return normalized.contains("CHAR") || normalized.contains("CLOB") || normalized.contains("TEXT")
        case .integer:
            return normalized.contains("INT") || normalized == "BOOLEAN" || normalized == "BOOL"
        case .real:
            return normalized.contains("REAL") || normalized.contains("FLOA") || normalized.contains("DOUB")
        case .blob:
            return normalized.contains("BLOB")
        }
    }
}

private struct SQLiteColumnInfo {
    let name: String
    let type: String
    let isPrimaryKey: Bool
}
