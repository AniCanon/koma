import Foundation

/// Errors thrown by Koma's JSON path.
///
/// This decoder is not a general `JSONDecoder` replacement. It is a narrow,
/// acceleration path for flat Koma records with supported stored column types.
@_documentation(visibility: private)
public enum KomaJSONFastPathError: Error, Equatable, Sendable {
    case emptyInput
    case unexpectedByte(UInt8, offset: Int)
    case unexpectedEnd
    case invalidNumber(offset: Int)
    case missingRequiredField(String)
    case integerOverflow(String)
    case unsupportedEscape(offset: Int)
    case nonFiniteNumber
    case unavailable
}

/// Entry points used by macro-expanded record code to decode JSON arrays and objects.
@_documentation(visibility: private)
public enum KomaJSONRecordDecoder {
    public static func decodeArray<Record>(
        from data: borrowing Data,
        _ decode: (inout KomaJSONScanner) throws -> Record
    ) throws -> [Record] {
        try decodeArray(from: data, estimatedBytesPerRecord: 0, decode)
    }

    public static func decodeArray<Record>(
        from data: borrowing Data,
        estimatedBytesPerRecord: Int,
        _ decode: (inout KomaJSONScanner) throws -> Record
    ) throws -> [Record] {
        try data.withUnsafeBytes { rawBuffer in
            guard !rawBuffer.isEmpty,
                  let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else {
                throw KomaJSONFastPathError.emptyInput
            }

            let buffer = UnsafeBufferPointer(start: baseAddress, count: rawBuffer.count)
            var scanner = KomaJSONScanner(buffer: buffer)
            let estimatedCount = if estimatedBytesPerRecord > 0 {
                max(1, rawBuffer.count / estimatedBytesPerRecord)
            } else {
                0
            }
            let records = try scanner.readArray(estimatedCount: estimatedCount, decode)
            try scanner.finish()
            return records
        }
    }

    public static func decodeObject<Record>(
        from data: borrowing Data,
        _ decode: (inout KomaJSONScanner) throws -> Record
    ) throws -> Record {
        try data.withUnsafeBytes { rawBuffer in
            guard !rawBuffer.isEmpty,
                  let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else {
                throw KomaJSONFastPathError.emptyInput
            }

            let buffer = UnsafeBufferPointer(start: baseAddress, count: rawBuffer.count)
            var scanner = KomaJSONScanner(buffer: buffer)
            let record = try decode(&scanner)
            try scanner.finish()
            return record
        }
    }

    public static func scanArray(
        from data: borrowing Data,
        _ consume: (inout KomaJSONScanner) throws -> Void
    ) throws {
        try data.withUnsafeBytes { rawBuffer in
            guard !rawBuffer.isEmpty,
                  let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else {
                throw KomaJSONFastPathError.emptyInput
            }

            let buffer = UnsafeBufferPointer(start: baseAddress, count: rawBuffer.count)
            var scanner = KomaJSONScanner(buffer: buffer)
            try scanner.scanArray(consume)
            try scanner.finish()
        }
    }
}

/// Entry points used by macro-expanded record code to encode JSON arrays and objects.
@_documentation(visibility: private)
public enum KomaJSONRecordEncoder {
    public static func encodeArray<Record>(
        _ records: borrowing [Record],
        _ encode: (Record, inout KomaJSONWriter) throws -> Void
    ) throws -> Data {
        try encodeArray(records, estimatedBytesPerRecord: 0, encode)
    }

    public static func encodeArray<Record>(
        _ records: borrowing [Record],
        estimatedBytesPerRecord: Int,
        _ encode: (Record, inout KomaJSONWriter) throws -> Void
    ) throws -> Data {
        let capacity = if estimatedBytesPerRecord > 0 {
            max(2, records.count * estimatedBytesPerRecord + 1)
        } else {
            256
        }
        var writer = KomaJSONWriter(capacity: capacity)
        writer.beginArray()
        var isFirst = true
        for index in records.indices {
            writer.writeCommaIfNeeded(isFirst: &isFirst)
            try encode(records[index], &writer)
        }
        writer.endArray()
        return writer.data()
    }

    public static func encodeObject<Record>(
        _ record: borrowing Record,
        _ encode: (Record, inout KomaJSONWriter) throws -> Void
    ) throws -> Data {
        var writer = KomaJSONWriter()
        try encode(record, &writer)
        return writer.data()
    }
}

@_documentation(visibility: private)
public func komaJSONRequire<Value>(_ value: Value?, _ field: StaticString) throws -> Value {
    guard let value else {
        throw KomaJSONFastPathError.missingRequiredField(String(describing: field))
    }
    return value
}
