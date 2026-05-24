import Foundation

/// A modular collection of entities, relationships, and migration packs.
public struct KomaSchema: @unchecked Sendable {
    public let entities: [any KomaEntityRecord.Type]
    public let relations: [any KomaRelationNamespace.Type]
    public let migrationPacks: [any KomaMigrationPack.Type]

    public init(
        entities: [any KomaEntityRecord.Type] = [],
        relations: [any KomaRelationNamespace.Type] = [],
        migrationPacks: [any KomaMigrationPack.Type] = []
    ) {
        self.entities = entities
        self.relations = relations
        self.migrationPacks = migrationPacks
    }

    public init(modules: [any KomaSchemaModule.Type]) {
        var entities: [any KomaEntityRecord.Type] = []
        var relations: [any KomaRelationNamespace.Type] = []
        var migrationPacks: [any KomaMigrationPack.Type] = []

        for module in modules {
            entities.append(contentsOf: module.entities)
            relations.append(contentsOf: module.relations)
            migrationPacks.append(contentsOf: module.migrationPacks)
        }

        self.entities = entities
        self.relations = relations
        self.migrationPacks = migrationPacks
    }
}

/// A feature-owned schema slice used to avoid one central migration file.
public protocol KomaSchemaModule {
    static var entities: [any KomaEntityRecord.Type] { get }
    static var relations: [any KomaRelationNamespace.Type] { get }
    static var migrationPacks: [any KomaMigrationPack.Type] { get }
}

public extension KomaSchemaModule {
    static var entities: [any KomaEntityRecord.Type] {
        []
    }

    static var relations: [any KomaRelationNamespace.Type] {
        []
    }

    static var migrationPacks: [any KomaMigrationPack.Type] {
        []
    }
}

/// A versioned migration pack owned by a feature or storage module.
public protocol KomaMigrationPack {
    static var namespace: String { get }
    static var migrations: [KomaMigration] { get }
}

/// A migration between two integer schema versions.
public struct KomaMigration: Equatable, Sendable {
    public let fromVersion: Int
    public let toVersion: Int
    public let steps: [KomaMigrationStep]

    public init(
        from fromVersion: Int,
        to toVersion: Int,
        @KomaMigrationBuilder steps: () -> [KomaMigrationStep]
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.steps = steps()
    }

    public init(
        _ fromVersion: Int,
        _ toVersion: Int,
        @KomaMigrationBuilder steps: () -> [KomaMigrationStep]
    ) {
        self.init(from: fromVersion, to: toVersion, steps: steps)
    }
}

@resultBuilder
public enum KomaMigrationBuilder {
    public static func buildBlock(_ components: [KomaMigrationStep]...) -> [KomaMigrationStep] {
        components.flatMap(\.self)
    }

    public static func buildArray(_ components: [[KomaMigrationStep]]) -> [KomaMigrationStep] {
        components.flatMap(\.self)
    }

    public static func buildEither(first component: [KomaMigrationStep]) -> [KomaMigrationStep] {
        component
    }

    public static func buildEither(second component: [KomaMigrationStep]) -> [KomaMigrationStep] {
        component
    }

    public static func buildOptional(_ component: [KomaMigrationStep]?) -> [KomaMigrationStep] {
        component ?? []
    }

    public static func buildExpression(_ expression: KomaMigrationStep) -> [KomaMigrationStep] {
        [expression]
    }
}

public enum KomaMigrationStep: Equatable, Sendable {
    case addColumn(table: String, column: KomaColumnMetadata, defaultValue: KomaValue?)
    case createTable(table: String, columns: [KomaColumnMetadata])
    case dropColumn(table: String, column: String)
    case renameColumn(table: String, from: String, to: String)
    case renameTable(from: String, to: String)
    case addIndex(table: String, columns: [String], name: String?, unique: Bool)
    case sql(String)
}

public func Migration(
    _ fromVersion: Int,
    _ toVersion: Int,
    @KomaMigrationBuilder steps: () -> [KomaMigrationStep]
) -> KomaMigration {
    KomaMigration(fromVersion, toVersion, steps: steps)
}

public func RenameColumn<Record: KomaEntityRecord>(
    _ record: Record.Type,
    from oldName: String,
    to keyPath: KeyPath<Record.Columns, KomaColumn<some Any>>
) -> KomaMigrationStep {
    .renameColumn(table: Record.komaTableName, from: oldName, to: Record.columns[keyPath: keyPath].name)
}

public func AddColumn<Record: KomaEntityRecord>(
    _ record: Record.Type,
    _ keyPath: KeyPath<Record.Columns, KomaColumn<some Any>>,
    storage: KomaStorageKind,
    default defaultValue: KomaValue? = nil
) -> KomaMigrationStep {
    let column = Record.columns[keyPath: keyPath].name
    return .addColumn(
        table: Record.komaTableName,
        column: KomaColumnMetadata(name: column, storage: storage),
        defaultValue: defaultValue
    )
}

public func DropColumn<Record: KomaEntityRecord>(
    _ record: Record.Type,
    _ column: String
) -> KomaMigrationStep {
    .dropColumn(table: Record.komaTableName, column: column)
}

public func RenameTable(
    from oldName: String,
    to newName: String
) -> KomaMigrationStep {
    .renameTable(from: oldName, to: newName)
}

public func CreateTable<Record: KomaEntityRecord>(
    _ record: Record.Type
) -> KomaMigrationStep {
    .createTable(table: Record.komaTableName, columns: Record.komaColumns)
}

public func AddIndex<Record: KomaEntityRecord>(
    _ record: Record.Type,
    _ keyPath: KeyPath<Record.Columns, KomaColumn<some Any>>,
    name: String? = nil,
    unique: Bool = false
) -> KomaMigrationStep {
    .addIndex(
        table: Record.komaTableName,
        columns: [Record.columns[keyPath: keyPath].name],
        name: name,
        unique: unique
    )
}

public func AddIndex<Record: KomaEntityRecord>(
    _ record: Record.Type,
    _ first: KeyPath<Record.Columns, KomaColumn<some Any>>,
    _ second: KeyPath<Record.Columns, KomaColumn<some Any>>,
    name: String? = nil,
    unique: Bool = false
) -> KomaMigrationStep {
    .addIndex(
        table: Record.komaTableName,
        columns: [
            Record.columns[keyPath: first].name,
            Record.columns[keyPath: second].name
        ],
        name: name,
        unique: unique
    )
}

public func AddIndex<Record: KomaEntityRecord>(
    _ record: Record.Type,
    _ first: KeyPath<Record.Columns, KomaColumn<some Any>>,
    _ second: KeyPath<Record.Columns, KomaColumn<some Any>>,
    _ third: KeyPath<Record.Columns, KomaColumn<some Any>>,
    name: String? = nil,
    unique: Bool = false
) -> KomaMigrationStep {
    .addIndex(
        table: Record.komaTableName,
        columns: [
            Record.columns[keyPath: first].name,
            Record.columns[keyPath: second].name,
            Record.columns[keyPath: third].name
        ],
        name: name,
        unique: unique
    )
}

public func SQL(_ sql: String) -> KomaMigrationStep {
    .sql(sql)
}
