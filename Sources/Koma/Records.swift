import Foundation

@_documentation(visibility: private)
public typealias KomaData = Data

/// A normalized value that Koma can store in a table.
///
/// Prefer declaring records with `@KomaEntity`; stored properties become
/// columns by default, `@KomaPrimaryKey` marks the primary key, and
/// `@KomaIgnore` excludes a stored property. If the transport model has matching
/// property names, pass `as:` to generate the default mapping.
///
/// ```swift
/// @KomaEntity(table: "projects", as: Project.self)
/// struct ProjectRecord: KomaRemoteRecord {
///     @KomaPrimaryKey var id: String
///     var name: String
///     var deletedAt: Date?
/// }
/// ```
public protocol KomaEntityRecord: Codable, Sendable {
    associatedtype Columns

    static var komaTableName: String { get }
    static var komaPrimaryKey: String { get }
    static var komaColumns: [KomaColumnMetadata] { get }
    static var columns: Columns { get }
}

@_documentation(visibility: private)
public protocol KomaGeneratedSchemaRecord: KomaEntityRecord {
    static var komaGeneratedCreateTableSQL: String? { get }
}

@_documentation(visibility: private)
public protocol KomaSQLiteFastPathRecord: KomaGeneratedSchemaRecord {
    static var komaUsesSQLiteFastPath: Bool { get }
    var komaSQLiteValues: [KomaSQLiteStorageValue] { get }

    func komaSQLiteValues(into values: inout [KomaSQLiteStorageValue])
    func komaSQLiteValue(at index: Int) -> KomaSQLiteStorageValue
    func komaSQLiteBind(into binder: inout some KomaSQLiteValueBinder) throws
    static func komaSQLiteRecord(from row: KomaSQLiteRow) throws -> Self
    static func komaSQLiteRecord(from reader: borrowing some KomaSQLiteRowReader) throws -> Self
}

@_documentation(visibility: private)
public protocol KomaJSONFastPathRecord: KomaEntityRecord {
    static var komaUsesJSONFastPath: Bool { get }

    static func komaJSONRecords(from data: borrowing Data) throws -> [Self]
    static func komaJSONRecord(from data: borrowing Data) throws -> Self
    static func komaJSONData(records: borrowing [Self]) throws -> Data
    func komaJSONData() throws -> Data
    func komaJSONWrite(to writer: inout KomaJSONWriter) throws
}

/// Record type that can scan JSON and bind store values in one pass.
@_documentation(visibility: private)
public protocol KomaFusedJSONRecord: KomaJSONFastPathRecord & KomaSQLiteFastPathRecord {
    static func komaJSONBindRecords<Binder: KomaSQLiteJSONValueBinder>(
        from data: borrowing Data,
        makeBinder: () throws -> Binder,
        finish: (inout Binder) throws -> Void
    ) throws
}

public extension KomaSQLiteFastPathRecord {
    static var komaUsesSQLiteFastPath: Bool {
        true
    }

    func komaSQLiteBind(into binder: inout some KomaSQLiteValueBinder) throws {
        var values: [KomaSQLiteStorageValue] = []
        komaSQLiteValues(into: &values)
        for value in values {
            try binder.bind(value)
        }
    }

    func komaSQLiteValue(at index: Int) -> KomaSQLiteStorageValue {
        komaSQLiteValues[index]
    }

    static func komaSQLiteRecord(from reader: borrowing some KomaSQLiteRowReader) throws -> Self {
        var values: [KomaSQLiteStorageValue] = []
        values.reserveCapacity(Self.komaColumns.count)
        for (index, column) in Self.komaColumns.enumerated() {
            switch column.storage {
            case .text:
                try values.append(reader._optionalString(at: index).map(KomaSQLiteStorageValue.text) ?? .null)
            case .integer:
                try values.append(reader._optionalInteger(at: index, as: Int64.self).map(KomaSQLiteStorageValue.integer) ?? .null)
            case .real:
                try values.append(reader._optionalReal(at: index, as: Double.self).map(KomaSQLiteStorageValue.real) ?? .null)
            case .blob:
                try values.append(reader._optionalData(at: index).map(KomaSQLiteStorageValue.blob) ?? .null)
            }
        }
        return try Self.komaSQLiteRecord(from: KomaSQLiteRow(values: values))
    }
}

public extension KomaJSONFastPathRecord {
    static var komaUsesJSONFastPath: Bool {
        true
    }
}

/// A record that can normalize a REST model and project itself back to that model.
///
/// Koma persists records, not opaque REST payload blobs. Use this protocol when
/// a resource response can be converted directly into one table.
public protocol KomaRemoteRecord: KomaEntityRecord {
    associatedtype Remote: Codable & Sendable

    init(remote: Remote)

    static func record(remote: Remote, context: KomaPersistenceContext) -> Self

    var remoteValue: Remote { get }
}

public extension KomaRemoteRecord {
    static func record(remote: Remote, context: KomaPersistenceContext) -> Self {
        Self(remote: remote)
    }
}

/// Describes a single stored column.
public struct KomaColumnMetadata: Equatable, Sendable {
    public let name: String
    public let storage: KomaStorageKind
    public let isPrimaryKey: Bool

    public init(name: String, storage: KomaStorageKind, isPrimaryKey: Bool = false) {
        self.name = name
        self.storage = storage
        self.isPrimaryKey = isPrimaryKey
    }
}

/// SQLite storage classes used by Koma records.
public enum KomaStorageKind: String, Equatable, Sendable {
    case text
    case integer
    case real
    case blob
}

/// A typed reference to a stored column.
public struct KomaColumn<Value>: Sendable {
    public let name: String
    @_documentation(visibility: private)
    public let index: Int?

    public init(_ name: String, index: Int? = nil) {
        self.name = name
        self.index = index
    }
}
