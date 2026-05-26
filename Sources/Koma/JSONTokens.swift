import Foundation

/// A JSON object key that can compare against static field names without allocating a `String`.
@_documentation(visibility: private)
public struct KomaJSONKey {
    private let buffer: UnsafeBufferPointer<UInt8>?
    private let range: Range<Int>
    private let escapedStringValue: String?

    public var stringValue: String {
        if let buffer {
            return String(decoding: buffer[range], as: UTF8.self)
        }
        return escapedStringValue ?? ""
    }

    @inline(__always)
    public var firstByte: UInt8 {
        if let buffer, let lowerBound = range.first {
            return buffer[lowerBound]
        }
        return escapedStringValue?.utf8.first ?? 0
    }

    init(buffer: UnsafeBufferPointer<UInt8>, range: Range<Int>) {
        self.buffer = buffer
        self.range = range
        escapedStringValue = nil
    }

    init(stringValue: String) {
        buffer = nil
        range = 0 ..< 0
        escapedStringValue = stringValue
    }

    @inline(__always)
    public func equals(_ key: StaticString) -> Bool {
        matches(
            key,
            count: key.utf8CodeUnitCount,
            firstByte: key.utf8Start[0],
            secondByte: key.utf8CodeUnitCount > 1 ? key.utf8Start[1] : 0,
            lastByte: key.utf8Start[key.utf8CodeUnitCount - 1]
        )
    }

    @inline(__always)
    public func matches(
        _ key: StaticString,
        count expectedCount: Int,
        firstByte expectedFirstByte: UInt8,
        secondByte expectedSecondByte: UInt8,
        lastByte expectedLastByte: UInt8
    ) -> Bool {
        if let buffer {
            let count = range.count
            guard count == expectedCount else {
                return false
            }
            let lowerBound = range.lowerBound
            guard buffer[lowerBound] == expectedFirstByte else {
                return false
            }
            if count > 1, buffer[lowerBound + 1] != expectedSecondByte {
                return false
            }
            if count > 2, buffer[range.upperBound - 1] != expectedLastByte {
                return false
            }
            let bytes = key.utf8Start
            guard count > 3 else {
                return true
            }
            for index in 2 ..< (count - 1) where buffer[lowerBound + index] != bytes[index] {
                return false
            }
            return true
        }

        guard let escapedStringValue,
              escapedStringValue.utf8.count == expectedCount,
              escapedStringValue.utf8.first == expectedFirstByte,
              escapedStringValue.utf8.last == expectedLastByte
        else {
            return false
        }

        let bytes = key.utf8Start
        for (index, byte) in escapedStringValue.utf8.enumerated() where byte != bytes[index] {
            return false
        }
        return true
    }
}

/// A JSON string value that can stay byte-backed for fused persistence paths.
///
/// The byte-backed storage is only valid while the scanner's input buffer is alive.
/// Consumers must copy or bind the bytes before returning from the scanner callback.
@_documentation(visibility: private)
public struct KomaJSONText {
    private let buffer: UnsafeBufferPointer<UInt8>?
    private let range: Range<Int>
    private let escapedStringValue: String?

    init(buffer: UnsafeBufferPointer<UInt8>, range: Range<Int>) {
        self.buffer = buffer
        self.range = range
        escapedStringValue = nil
    }

    init(stringValue: String) {
        buffer = nil
        range = 0 ..< 0
        escapedStringValue = stringValue
    }

    public func withUnsafeUTF8<Result>(
        _ body: (UnsafeBufferPointer<UInt8>) throws -> Result
    ) rethrows -> Result {
        if let buffer {
            guard !range.isEmpty else {
                return try body(UnsafeBufferPointer(start: nil, count: 0))
            }
            let pointer = buffer.baseAddress?.advanced(by: range.lowerBound)
            return try body(UnsafeBufferPointer(start: pointer, count: range.count))
        }

        let value = escapedStringValue ?? ""
        if let result = try value.utf8.withContiguousStorageIfAvailable(body) {
            return result
        }
        let bytes = Array(value.utf8)
        return try bytes.withUnsafeBufferPointer(body)
    }
}
