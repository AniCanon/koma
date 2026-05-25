import Foundation

/// A forward-only JSON scanner used by macro-expanded record decoders.
@_documentation(visibility: private)
public struct KomaJSONScanner {
    let buffer: UnsafeBufferPointer<UInt8>
    var offset = 0

    public mutating func readArray<Element>(
        _ decode: (inout KomaJSONScanner) throws -> Element
    ) throws -> [Element] {
        try readArray(estimatedCount: 0, decode)
    }

    public mutating func readArray<Element>(
        estimatedCount: Int,
        _ decode: (inout KomaJSONScanner) throws -> Element
    ) throws -> [Element] {
        try expect(.leftBracket)
        try skipWhitespace()

        var elements: [Element] = []
        if estimatedCount > 0 {
            elements.reserveCapacity(estimatedCount)
        }
        guard !consumeIf(.rightBracket) else {
            return elements
        }

        while true {
            try elements.append(decode(&self))
            try skipWhitespace()
            if consumeIf(.comma) {
                continue
            }
            try expect(.rightBracket)
            return elements
        }
    }

    public mutating func scanArray(
        _ consume: (inout KomaJSONScanner) throws -> Void
    ) throws {
        try expect(.leftBracket)
        try skipWhitespace()

        guard !consumeIf(.rightBracket) else {
            return
        }

        while true {
            try consume(&self)
            try skipWhitespace()
            if consumeIf(.comma) {
                continue
            }
            try expect(.rightBracket)
            return
        }
    }

    public mutating func readObject(
        _ consumeValueForKey: (String, inout KomaJSONScanner) throws -> Void
    ) throws {
        try readObjectKeyed { key, scanner in
            try consumeValueForKey(key.stringValue, &scanner)
        }
    }

    public mutating func readObjectKeyed(
        _ consumeValueForKey: (KomaJSONKey, inout KomaJSONScanner) throws -> Void
    ) throws {
        try expect(.leftBrace)
        try skipWhitespace()

        guard !consumeIf(.rightBrace) else {
            return
        }

        while true {
            let key = try readKey()
            try expect(.colon)
            try consumeValueForKey(key, &self)
            try skipWhitespace()
            if consumeIf(.comma) {
                continue
            }
            try expect(.rightBrace)
            return
        }
    }

    public mutating func readString() throws -> String {
        try expect(.quote)
        let start = offset

        while offset < buffer.count {
            let byte = buffer[offset]
            if byte == JSONByte.quote.rawValue {
                let end = offset
                offset += 1
                return String(decoding: buffer[start ..< end], as: UTF8.self)
            }
            if byte == JSONByte.backslash.rawValue {
                return try readEscapedString(start: start)
            }
            offset += 1
        }

        throw KomaJSONFastPathError.unexpectedEnd
    }

    public mutating func readText() throws -> KomaJSONText {
        try expect(.quote)
        let start = offset

        while offset < buffer.count {
            let byte = buffer[offset]
            if byte == JSONByte.quote.rawValue {
                let end = offset
                offset += 1
                return KomaJSONText(buffer: buffer, range: start ..< end)
            }
            if byte == JSONByte.backslash.rawValue {
                return try KomaJSONText(stringValue: readEscapedString(start: start))
            }
            offset += 1
        }

        throw KomaJSONFastPathError.unexpectedEnd
    }

    public mutating func readKey() throws -> KomaJSONKey {
        try expect(.quote)
        let start = offset

        while offset < buffer.count {
            let byte = buffer[offset]
            if byte == JSONByte.quote.rawValue {
                let end = offset
                offset += 1
                return KomaJSONKey(buffer: buffer, range: start ..< end)
            }
            if byte == JSONByte.backslash.rawValue {
                return try KomaJSONKey(stringValue: readEscapedString(start: start))
            }
            offset += 1
        }

        throw KomaJSONFastPathError.unexpectedEnd
    }

    public mutating func readOptionalString() throws -> String? {
        if try consumeNullIfPresent() {
            return nil
        }
        return try readString()
    }

    public mutating func readOptionalText() throws -> KomaJSONText? {
        if try consumeNullIfPresent() {
            return nil
        }
        return try readText()
    }

    public mutating func readBool() throws -> Bool {
        try skipWhitespace()
        if consumeLiteral("true") {
            return true
        }
        if consumeLiteral("false") {
            return false
        }
        throw unexpectedByte()
    }

    public mutating func readOptionalBool() throws -> Bool? {
        if try consumeNullIfPresent() {
            return nil
        }
        return try readBool()
    }

    public mutating func readInteger<Value: FixedWidthInteger & SignedInteger>(
        as type: Value.Type = Value.self
    ) throws -> Value {
        let value = try readInt64()
        guard let converted = Value(exactly: value) else {
            throw KomaJSONFastPathError.integerOverflow(String(describing: type))
        }
        return converted
    }

    public mutating func readOptionalInteger<Value: FixedWidthInteger & SignedInteger>(
        as type: Value.Type = Value.self
    ) throws -> Value? {
        if try consumeNullIfPresent() {
            return nil
        }
        return try readInteger(as: type)
    }

    public mutating func readDouble() throws -> Double {
        try readDoubleValue()
    }

    public mutating func readOptionalDouble() throws -> Double? {
        if try consumeNullIfPresent() {
            return nil
        }
        return try readDouble()
    }

    public mutating func readFloat() throws -> Float {
        try Float(readDouble())
    }

    public mutating func readOptionalFloat() throws -> Float? {
        if try consumeNullIfPresent() {
            return nil
        }
        return try readFloat()
    }

    public mutating func readDate() throws -> Date {
        try Date(timeIntervalSinceReferenceDate: readDouble())
    }

    public mutating func readOptionalDate() throws -> Date? {
        try readOptionalDouble().map(Date.init(timeIntervalSinceReferenceDate:))
    }

    public mutating func skipValue() throws {
        try skipWhitespace()
        guard let byte = peek() else {
            throw KomaJSONFastPathError.unexpectedEnd
        }

        switch byte {
        case JSONByte.leftBrace.rawValue:
            try readObject { _, scanner in
                try scanner.skipValue()
            }
        case JSONByte.leftBracket.rawValue:
            try expect(.leftBracket)
            try skipWhitespace()
            guard !consumeIf(.rightBracket) else {
                return
            }
            while true {
                try skipValue()
                try skipWhitespace()
                if consumeIf(.comma) {
                    continue
                }
                try expect(.rightBracket)
                return
            }
        case JSONByte.quote.rawValue:
            _ = try readString()
        case JSONByte.t.rawValue, JSONByte.f.rawValue:
            _ = try readBool()
        case JSONByte.n.rawValue:
            guard try consumeNullIfPresent() else {
                throw unexpectedByte()
            }
        default:
            _ = try readNumberRange()
        }
    }

    public mutating func finish() throws {
        try skipWhitespace()
        guard offset == buffer.count else {
            throw unexpectedByte()
        }
    }
}
