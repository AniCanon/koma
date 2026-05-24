import Foundation

/// A small JSON writer used by macro-expanded Koma record encoders.
@_documentation(visibility: private)
public struct _KomaJSONWriter {
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

    public mutating func writeField(
        _ key: StaticString,
        _ value: some FixedWidthInteger,
        isFirst: inout Bool
    ) throws {
        writeKey(key, isFirst: &isFirst)
        writeInteger(value)
    }

    public mutating func writeField(
        _ key: StaticString,
        _ value: (some FixedWidthInteger)?,
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
            throw _KomaJSONError.nonFiniteNumber
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

    private mutating func writeString(_ value: String) {
        bytes.append(JSONByte.quote.rawValue)
        for byte in value.utf8 {
            writeStringByte(byte)
        }
        bytes.append(JSONByte.quote.rawValue)
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
        writeRaw(value ? "true" : "false")
    }

    private mutating func writeInteger(_ value: some FixedWidthInteger) {
        writeRaw(String(value))
    }

    private mutating func writeRaw(_ value: String) {
        bytes.append(contentsOf: value.utf8)
    }

    private static func hexDigit(_ value: UInt8) -> UInt8 {
        value < 10 ? 48 + value : 87 + value
    }
}
