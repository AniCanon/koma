import Foundation

/// Errors thrown by Koma's JSON path.
///
/// This decoder is not a general `JSONDecoder` replacement. It is a narrow,
/// acceleration path for flat Koma records with supported stored column types.
@_documentation(visibility: private)
public enum _KomaJSONError: Error, Equatable, Sendable {
    case emptyInput
    case unexpectedByte(UInt8, offset: Int)
    case unexpectedEnd
    case invalidNumber(offset: Int)
    case missingRequiredField(String)
    case integerOverflow(String)
    case unsupportedEscape(offset: Int)
    case unavailable
}

/// Entry points used by macro-expanded record code to decode JSON arrays and objects.
@_documentation(visibility: private)
public enum _KomaJSONDecoder {
    public static func decodeArray<Record>(
        from data: borrowing Data,
        _ decode: (inout _KomaJSONScanner) throws -> Record
    ) throws -> [Record] {
        try data.withUnsafeBytes { rawBuffer in
            guard !rawBuffer.isEmpty,
                  let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else {
                throw _KomaJSONError.emptyInput
            }

            let buffer = UnsafeBufferPointer(start: baseAddress, count: rawBuffer.count)
            var scanner = _KomaJSONScanner(buffer: buffer)
            let records = try scanner.readArray(decode)
            try scanner.finish()
            return records
        }
    }

    public static func decodeObject<Record>(
        from data: borrowing Data,
        _ decode: (inout _KomaJSONScanner) throws -> Record
    ) throws -> Record {
        try data.withUnsafeBytes { rawBuffer in
            guard !rawBuffer.isEmpty,
                  let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            else {
                throw _KomaJSONError.emptyInput
            }

            let buffer = UnsafeBufferPointer(start: baseAddress, count: rawBuffer.count)
            var scanner = _KomaJSONScanner(buffer: buffer)
            let record = try decode(&scanner)
            try scanner.finish()
            return record
        }
    }
}

@_documentation(visibility: private)
public func _komaJSONRequire<Value>(_ value: Value?, _ field: StaticString) throws -> Value {
    guard let value else {
        throw _KomaJSONError.missingRequiredField(String(describing: field))
    }
    return value
}
