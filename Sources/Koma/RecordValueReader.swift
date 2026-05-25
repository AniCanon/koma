import Foundation

enum KomaRecordValueReader {
    static func value<Record: KomaEntityRecord>(_ column: String, in record: Record) throws -> KomaValue {
        if let fastRecord = record as? any KomaSQLiteFastPathRecord,
           let index = Record.komaColumns.firstIndex(where: { $0.name == column })
        {
            return try value(fastRecord.komaSQLiteValue(at: index), column: column)
        }

        let data = try JSONEncoder().encode(record)
        let object = try (JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard let rawValue = object[column], !(rawValue is NSNull) else {
            throw KomaModelError.missingColumnValue(column)
        }
        return try value(rawValue, column: column)
    }

    private static func value(_ value: KomaSQLiteStorageValue, column: String) throws -> KomaValue {
        switch value {
        case let .text(value):
            return .string(value)
        case let .integer(value):
            return .int(value)
        case let .real(value):
            return .double(value)
        case .blob, .null:
            throw KomaModelError.unsupportedRelationValue(column)
        }
    }

    private static func value(_ value: Any, column: String) throws -> KomaValue {
        switch value {
        case let value as String:
            return .string(value)
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .int(Int64(value))
        case let value as Int64:
            return .int(value)
        case let value as Double:
            return .double(value)
        case let value as NSNumber:
            return .double(value.doubleValue)
        default:
            throw KomaModelError.unsupportedRelationValue(column)
        }
    }
}

public enum KomaModelError: Error, Equatable, LocalizedError {
    case missingColumnValue(String)
    case unsupportedRelationValue(String)

    public var errorDescription: String? {
        switch self {
        case let .missingColumnValue(column):
            return "Missing relation column value for \(column)."
        case let .unsupportedRelationValue(column):
            return "Unsupported relation column value for \(column)."
        }
    }
}
