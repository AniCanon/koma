extension KomaJSONScanner {
    @inline(__always)
    mutating func skipWhitespace() throws {
        while let byte = peek(), byte == 32 || byte == 10 || byte == 13 || byte == 9 {
            offset += 1
        }
    }

    @inline(__always)
    func peek() -> UInt8? {
        offset < buffer.count ? buffer[offset] : nil
    }

    @inline(__always)
    mutating func consumeIf(_ byte: JSONByte) -> Bool {
        guard peek() == byte.rawValue else {
            return false
        }
        offset += 1
        return true
    }

    @inline(__always)
    mutating func expect(_ byte: JSONByte) throws {
        try skipWhitespace()
        guard consumeIf(byte) else {
            throw unexpectedByte()
        }
    }

    mutating func consumeNullIfPresent() throws -> Bool {
        try skipWhitespace()
        return consumeLiteral("null")
    }

    mutating func consumeLiteral(_ literal: StaticString) -> Bool {
        let bytes = literal.utf8Start
        guard offset + literal.utf8CodeUnitCount <= buffer.count else {
            return false
        }
        for index in 0 ..< literal.utf8CodeUnitCount where buffer[offset + index] != bytes[index] {
            return false
        }
        offset += literal.utf8CodeUnitCount
        return true
    }

    func unexpectedByte() -> KomaJSONFastPathError {
        guard let byte = peek() else {
            return .unexpectedEnd
        }
        return .unexpectedByte(byte, offset: offset)
    }
}
