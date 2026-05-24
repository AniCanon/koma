import Foundation

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
    static var _komaSQLiteCreateTableSQL: String? { get }
    static var _komaSQLiteFastPath: Bool { get }
    var _komaSQLiteValues: [_KomaSQLiteValue] { get }
    static var _komaJSONFastPath: Bool { get }

    func _komaSQLiteValues(into values: inout [_KomaSQLiteValue])
    func _komaSQLiteBind(into binder: inout some _KomaSQLiteValueBinder) throws
    static func _komaSQLiteRecord(from row: _KomaSQLiteRow) throws -> Self
    static func _komaSQLiteRecord(from reader: borrowing some _KomaSQLiteRowReader) throws -> Self
    static func _komaJSONRecords(from data: borrowing Data) throws -> [Self]
    static func _komaJSONRecord(from data: borrowing Data) throws -> Self
}

public extension KomaEntityRecord {
    static var _komaSQLiteCreateTableSQL: String? {
        nil
    }

    static var _komaSQLiteFastPath: Bool {
        false
    }

    var _komaSQLiteValues: [_KomaSQLiteValue] {
        []
    }

    static var _komaJSONFastPath: Bool {
        false
    }

    func _komaSQLiteValues(into values: inout [_KomaSQLiteValue]) {
        values.append(contentsOf: _komaSQLiteValues)
    }

    func _komaSQLiteBind(into binder: inout some _KomaSQLiteValueBinder) throws {
        var values: [_KomaSQLiteValue] = []
        _komaSQLiteValues(into: &values)
        for value in values {
            try binder.bind(value)
        }
    }

    static func _komaSQLiteRecord(from row: _KomaSQLiteRow) throws -> Self {
        throw _KomaSQLiteFastPathError.unavailable
    }

    static func _komaSQLiteRecord(from reader: borrowing some _KomaSQLiteRowReader) throws -> Self {
        var values: [_KomaSQLiteValue] = []
        values.reserveCapacity(Self.komaColumns.count)
        for (index, column) in Self.komaColumns.enumerated() {
            switch column.storage {
            case .text:
                try values.append(reader._optionalString(at: index).map(_KomaSQLiteValue.text) ?? .null)
            case .integer:
                try values.append(reader._optionalInteger(at: index, as: Int64.self).map(_KomaSQLiteValue.integer) ?? .null)
            case .real:
                try values.append(reader._optionalReal(at: index, as: Double.self).map(_KomaSQLiteValue.real) ?? .null)
            case .blob:
                try values.append(reader._optionalData(at: index).map(_KomaSQLiteValue.blob) ?? .null)
            }
        }
        return try Self._komaSQLiteRecord(from: _KomaSQLiteRow(values: values))
    }

    static func _komaJSONRecords(from data: borrowing Data) throws -> [Self] {
        throw _KomaJSONError.unavailable
    }

    static func _komaJSONRecord(from data: borrowing Data) throws -> Self {
        throw _KomaJSONError.unavailable
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

    public init(_ name: String) {
        self.name = name
    }
}
