import Foundation
import Koma

/// A single row from a raw SQL query, with columns addressable by name.
///
/// Non-optional accessors throw if the column is missing, `NULL`, or holds a different
/// storage type; the `optional…` accessors return `nil` for `NULL`.
public struct KomaRawRow: Sendable {
    private let values: [KomaSQLiteStorageValue]
    private let columnIndex: [String: Int]

    init(values: [KomaSQLiteStorageValue], columnIndex: [String: Int]) {
        self.values = values
        self.columnIndex = columnIndex
    }

    public func int(_ column: String) throws -> Int {
        guard case let .integer(value) = try storageValue(for: column) else {
            throw mismatch(column, "integer")
        }
        return Int(value)
    }

    public func double(_ column: String) throws -> Double {
        guard case let .real(value) = try storageValue(for: column) else {
            throw mismatch(column, "real")
        }
        return value
    }

    public func string(_ column: String) throws -> String {
        guard case let .text(value) = try storageValue(for: column) else {
            throw mismatch(column, "text")
        }
        return value
    }

    public func bool(_ column: String) throws -> Bool {
        guard case let .integer(value) = try storageValue(for: column) else {
            throw mismatch(column, "integer")
        }
        return value != 0
    }

    public func data(_ column: String) throws -> Data {
        guard case let .blob(value) = try storageValue(for: column) else {
            throw mismatch(column, "blob")
        }
        return value
    }

    public func optionalInt(_ column: String) throws -> Int? {
        try isNull(column) ? nil : int(column)
    }

    public func optionalDouble(_ column: String) throws -> Double? {
        try isNull(column) ? nil : double(column)
    }

    public func optionalString(_ column: String) throws -> String? {
        try isNull(column) ? nil : string(column)
    }

    public func optionalBool(_ column: String) throws -> Bool? {
        try isNull(column) ? nil : bool(column)
    }

    public func optionalData(_ column: String) throws -> Data? {
        try isNull(column) ? nil : data(column)
    }

    /// Whether the named column is `NULL`.
    public func isNull(_ column: String) throws -> Bool {
        if case .null = try storageValue(for: column) {
            return true
        }
        return false
    }

    private func storageValue(for column: String) throws -> KomaSQLiteStorageValue {
        guard let index = columnIndex[column] else {
            throw SQLiteKomaError.executionFailed("No column named '\(column)' in the result set.")
        }
        return values[index]
    }

    private func mismatch(_ column: String, _ expected: String) -> SQLiteKomaError {
        .executionFailed("Column '\(column)' is not \(expected).")
    }
}
