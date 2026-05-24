import CKomaSQLite
import Foundation
import Koma

extension SQLiteKomaStore {
    func applyMigrationPacks(_ packs: [any KomaMigrationPack.Type]) throws {
        guard !packs.isEmpty else {
            return
        }

        try prepareMigrationMetadata()
        for pack in packs {
            try applyMigrationPack(pack)
        }
    }

    func applyLatestSchemaArtifacts(_ packs: [any KomaMigrationPack.Type]) throws {
        for pack in packs {
            for migration in pack.migrations {
                for step in migration.steps {
                    if case .addIndex = step {
                        try execute(migrationStep: step)
                    }
                }
            }
        }
    }

    private func applyMigrationPack(_ pack: any KomaMigrationPack.Type) throws {
        let migrations = pack.migrations.sorted { lhs, rhs in
            if lhs.fromVersion == rhs.fromVersion {
                return lhs.toVersion < rhs.toVersion
            }
            return lhs.fromVersion < rhs.fromVersion
        }
        guard let firstVersion = migrations.map(\.fromVersion).min(),
              let latestVersion = migrations.map(\.toVersion).max()
        else {
            return
        }

        var version: Int
        if let storedVersion = try migrationVersion(namespace: pack.namespace) {
            version = storedVersion
        } else if try hasUserTables() {
            version = firstVersion
        } else {
            try setMigrationVersion(namespace: pack.namespace, version: latestVersion)
            return
        }

        for migration in migrations {
            if migration.toVersion <= version {
                continue
            }

            guard migration.fromVersion == version else {
                throw SQLiteKomaError.migrationFailed(
                    "Missing migration for \(pack.namespace) from version \(version) to \(migration.fromVersion)."
                )
            }

            try execute("BEGIN IMMEDIATE TRANSACTION")
            do {
                for step in migration.steps {
                    try execute(migrationStep: step)
                }
                try setMigrationVersion(namespace: pack.namespace, version: migration.toVersion)
                try execute("COMMIT")
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
            version = migration.toVersion
        }
    }

    private func prepareMigrationMetadata() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS "_koma_migration_versions" (
                "namespace" TEXT PRIMARY KEY NOT NULL,
                "version" INTEGER NOT NULL
            )
            """
        )
    }

    private func migrationVersion(namespace: String) throws -> Int? {
        try withStatement("SELECT version FROM \"_koma_migration_versions\" WHERE namespace = ? LIMIT 1") { statement in
            sqlite3_bind_text(statement, 1, namespace, -1, SQLITE_TRANSIENT)
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                return Int(sqlite3_column_int64(statement, 0))
            }
            guard step == SQLITE_DONE else {
                throw SQLiteKomaError.executionFailed("Unable to read Koma migration version.")
            }
            return nil
        }
    }

    private func setMigrationVersion(namespace: String, version: Int) throws {
        let sql = """
        INSERT INTO "_koma_migration_versions" ("namespace", "version")
        VALUES (?, ?)
        ON CONFLICT("namespace") DO UPDATE SET "version" = excluded."version"
        """
        try withStatement(sql) { statement in
            sqlite3_bind_text(statement, 1, namespace, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 2, Int64(version))
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw SQLiteKomaError.executionFailed("Unable to persist Koma migration version.")
            }
        }
    }

    private func hasUserTables() throws -> Bool {
        let sql = """
        SELECT 1 FROM sqlite_master
        WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
        AND name NOT LIKE '_koma_%'
        LIMIT 1
        """
        return try withStatement(sql) { statement in
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                return true
            }
            guard step == SQLITE_DONE else {
                throw SQLiteKomaError.executionFailed("Unable to inspect SQLite tables.")
            }
            return false
        }
    }

    private func execute(migrationStep step: KomaMigrationStep) throws {
        switch step {
        case let .addColumn(table, column, defaultValue):
            var sql = "ALTER TABLE \(Self.quote(table)) ADD COLUMN \(Self.quote(column.name)) \(column.storage.sqliteType)"
            if let defaultValue {
                sql += " DEFAULT \(Self.literal(defaultValue))"
            }
            try execute(sql)
        case let .createTable(table, columns):
            try createTable(tableName: table, columns: columns)
        case let .dropColumn(table, column):
            try execute("ALTER TABLE \(Self.quote(table)) DROP COLUMN \(Self.quote(column))")
        case let .renameColumn(table, oldName, newName):
            try execute(
                "ALTER TABLE \(Self.quote(table)) RENAME COLUMN \(Self.quote(oldName)) TO \(Self.quote(newName))"
            )
        case let .renameTable(oldName, newName):
            try execute("ALTER TABLE \(Self.quote(oldName)) RENAME TO \(Self.quote(newName))")
        case let .addIndex(table, columns, name, unique):
            guard !columns.isEmpty else {
                throw SQLiteKomaError.migrationFailed("Cannot create an index without columns.")
            }
            let indexName = name ?? "idx_\(table)_\(columns.joined(separator: "_"))"
            let uniqueness = unique ? "UNIQUE " : ""
            let columnList = Self.quotedColumnList(columns)
            try execute("CREATE \(uniqueness)INDEX IF NOT EXISTS \(Self.quote(indexName)) ON \(Self.quote(table)) (\(columnList))")
        case let .sql(sql):
            try execute(sql)
        }
    }

    private static func literal(_ value: KomaValue) -> String {
        switch value {
        case let .string(value):
            return "'\(value.replacingOccurrences(of: "'", with: "''"))'"
        case let .int(value):
            return "\(value)"
        case let .double(value):
            return "\(value)"
        case let .bool(value):
            return value ? "1" : "0"
        }
    }
}
