import Foundation

/// A small JSON writer used by macro-expanded Koma record encoders.
@_documentation(visibility: private)
public struct KomaJSONWriter {
    private var bytes: [UInt8]

    public init(capacity: Int = 256) {
        bytes = []
        bytes.reserveCapacity(capacity)
    }

    public func data() -> Data {
        Data(bytes)
    }

    public mutating func beginArray() {
        bytes.append(JSONByte.leftBracket.rawValue)
    }

    public mutating func endArray() {
        bytes.append(JSONByte.rightBracket.rawValue)
    }

    public mutating func beginObject() {
        bytes.append(JSONByte.leftBrace.rawValue)
    }

    public mutating func endObject() {
        bytes.append(JSONByte.rightBrace.rawValue)
    }

    public mutating func writeCommaIfNeeded(isFirst: inout Bool) {
        if isFirst {
            isFirst = false
        } else {
            bytes.append(JSONByte.comma.rawValue)
        }
    }

    public mutating func writeField(_ key: StaticString, _ value: String, isFirst: inout Bool) throws {
        writeKey(key, isFirst: &isFirst)
        writeString(value)
    }

    public mutating func writeField(_ key: StaticString, _ value: String?, isFirst: inout Bool) throws {
        guard let value else {
            return
        }
        try writeField(key, value, isFirst: &isFirst)
    }

    public mutating func writeField(_ key: StaticString, _ value: Bool, isFirst: inout Bool) throws {
        writeKey(key, isFirst: &isFirst)
        writeBool(value)
    }

    public mutating func writeField(_ key: StaticString, _ value: Bool?, isFirst: inout Bool) throws {
        guard let value else {
            return
        }
        try writeField(key, value, isFirst: &isFirst)
    }

    /// Exported specializations keep macro-generated encoders in other modules off the
    /// generic-metadata path (see the matching readInteger specializations in JSONScanner).
    @_specialize(exported: true, where Value == Int)
    @_specialize(exported: true, where Value == Int64)
    @_specialize(exported: true, where Value == Int32)
    @_specialize(exported: true, where Value == Int16)
    @_specialize(exported: true, where Value == Int8)
    public mutating func writeField<Value: FixedWidthInteger>(
        _ key: StaticString,
        _ value: Value,
        isFirst: inout Bool
    ) throws {
        writeKey(key, isFirst: &isFirst)
        writeInteger(value)
    }

    @_specialize(exported: true, where Value == Int)
    @_specialize(exported: true, where Value == Int64)
    @_specialize(exported: true, where Value == Int32)
    @_specialize(exported: true, where Value == Int16)
    @_specialize(exported: true, where Value == Int8)
    public mutating func writeField<Value: FixedWidthInteger>(
        _ key: StaticString,
        _ value: Value?,
        isFirst: inout Bool
    ) throws {
        guard let value else {
            return
        }
        try writeField(key, value, isFirst: &isFirst)
    }

    public mutating func writeField(_ key: StaticString, _ value: Float, isFirst: inout Bool) throws {
        try writeField(key, Double(value), isFirst: &isFirst)
    }

    public mutating func writeField(_ key: StaticString, _ value: Float?, isFirst: inout Bool) throws {
        guard let value else {
            return
        }
        try writeField(key, value, isFirst: &isFirst)
    }

    public mutating func writeField(_ key: StaticString, _ value: Double, isFirst: inout Bool) throws {
        guard value.isFinite else {
            throw KomaJSONFastPathError.nonFiniteNumber
        }
        writeKey(key, isFirst: &isFirst)
        writeRaw(String(value))
    }

    public mutating func writeField(_ key: StaticString, _ value: Double?, isFirst: inout Bool) throws {
        guard let value else {
            return
        }
        try writeField(key, value, isFirst: &isFirst)
    }

    public mutating func writeField(_ key: StaticString, _ value: Date, isFirst: inout Bool) throws {
        try writeField(key, value.timeIntervalSinceReferenceDate, isFirst: &isFirst)
    }

    public mutating func writeField(_ key: StaticString, _ value: Date?, isFirst: inout Bool) throws {
        guard let value else {
            return
        }
        try writeField(key, value, isFirst: &isFirst)
    }

    private mutating func writeKey(_ key: StaticString, isFirst: inout Bool) {
        writeCommaIfNeeded(isFirst: &isFirst)
        bytes.append(JSONByte.quote.rawValue)
        let buffer = UnsafeBufferPointer(start: key.utf8Start, count: key.utf8CodeUnitCount)
        bytes.append(contentsOf: buffer)
        bytes.append(JSONByte.quote.rawValue)
        bytes.append(JSONByte.colon.rawValue)
    }

    /// Writes a quoted, escaped JSON string. The scan walks the UTF-8 bytes a word at a time
    /// (SWAR — hardware-SIMD types pessimize short payloads here, see the scanner) and bulk-appends
    /// maximal runs that need no escaping, so the per-byte escape switch only runs on the rare
    /// quote/backslash/control bytes.
    private mutating func writeString(_ value: String) {
        bytes.append(JSONByte.quote.rawValue)
        var value = value
        value.withUTF8 { buffer in
            guard let base = buffer.baseAddress else { return }
            let count = buffer.count
            var start = 0
            var index = 0
            while index < count {
                if index + 8 <= count,
                   Self.escapeCandidates(UnsafeRawPointer(base + index).loadUnaligned(as: UInt64.self)) == 0
                {
                    index += 8
                    continue
                }
                let byte = buffer[index]
                if Self.needsEscape(byte) {
                    if index > start {
                        bytes.append(contentsOf: UnsafeBufferPointer(rebasing: buffer[start ..< index]))
                    }
                    writeStringByte(byte)
                    start = index + 1
                }
                index += 1
            }
            if count > start {
                bytes.append(contentsOf: UnsafeBufferPointer(rebasing: buffer[start ..< count]))
            }
        }
        bytes.append(JSONByte.quote.rawValue)
    }

    private static func needsEscape(_ byte: UInt8) -> Bool {
        byte < 0x20 || byte == JSONByte.quote.rawValue || byte == JSONByte.backslash.rawValue
    }

    /// Flags any byte of `word` that is a quote, backslash, or control byte (the standard
    /// SWAR has-less/has-value bit tricks; high bits of multi-byte UTF-8 never flag).
    private static func escapeCandidates(_ word: UInt64) -> UInt64 {
        let ones: UInt64 = 0x0101_0101_0101_0101
        let highs: UInt64 = 0x8080_8080_8080_8080
        let belowSpace = (word &- 0x2020_2020_2020_2020) & ~word & highs
        let quotes = word ^ (ones &* UInt64(JSONByte.quote.rawValue))
        let backslashes = word ^ (ones &* UInt64(JSONByte.backslash.rawValue))
        let isQuote = (quotes &- ones) & ~quotes & highs
        let isBackslash = (backslashes &- ones) & ~backslashes & highs
        return belowSpace | isQuote | isBackslash
    }

    private mutating func writeStringByte(_ byte: UInt8) {
        switch byte {
        case JSONByte.quote.rawValue:
            bytes.append(JSONByte.backslash.rawValue)
            bytes.append(JSONByte.quote.rawValue)
        case JSONByte.backslash.rawValue:
            bytes.append(JSONByte.backslash.rawValue)
            bytes.append(JSONByte.backslash.rawValue)
        case 8:
            bytes.append(JSONByte.backslash.rawValue)
            bytes.append(JSONByte.b.rawValue)
        case 12:
            bytes.append(JSONByte.backslash.rawValue)
            bytes.append(JSONByte.f.rawValue)
        case 10:
            bytes.append(JSONByte.backslash.rawValue)
            bytes.append(JSONByte.n.rawValue)
        case 13:
            bytes.append(JSONByte.backslash.rawValue)
            bytes.append(JSONByte.r.rawValue)
        case 9:
            bytes.append(JSONByte.backslash.rawValue)
            bytes.append(JSONByte.t.rawValue)
        case 0 ... 31:
            writeControlEscape(byte)
        default:
            bytes.append(byte)
        }
    }

    private mutating func writeControlEscape(_ byte: UInt8) {
        bytes.append(JSONByte.backslash.rawValue)
        bytes.append(JSONByte.u.rawValue)
        bytes.append(48)
        bytes.append(48)
        bytes.append(Self.hexDigit(byte >> 4))
        bytes.append(Self.hexDigit(byte & 0x0F))
    }

    private mutating func writeBool(_ value: Bool) {
        if value {
            bytes.append(contentsOf: [116, 114, 117, 101]) // true
        } else {
            bytes.append(contentsOf: [102, 97, 108, 115, 101]) // false
        }
    }

    /// Writes the decimal digits straight into the buffer — no intermediate `String`.
    private mutating func writeInteger(_ value: some FixedWidthInteger) {
        guard value != 0 else {
            bytes.append(48)
            return
        }
        var magnitude = value.magnitude
        // 40 covers the digits of any FixedWidthInteger up to 128 bits, plus a sign.
        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 40) { digits in
            var position = digits.count
            while magnitude != 0 {
                position -= 1
                digits[position] = 48 + UInt8(truncatingIfNeeded: magnitude % 10)
                magnitude /= 10
            }
            if value < 0 {
                position -= 1
                digits[position] = 45 // -
            }
            bytes.append(contentsOf: UnsafeBufferPointer(rebasing: digits[position...]))
        }
    }

    private mutating func writeRaw(_ value: String) {
        var value = value
        value.withUTF8 { bytes.append(contentsOf: $0) }
    }

    private static func hexDigit(_ value: UInt8) -> UInt8 {
        value < 10 ? 48 + value : 87 + value
    }
}
