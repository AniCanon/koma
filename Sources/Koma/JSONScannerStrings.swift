import Foundation

extension _KomaJSONScanner {
    mutating func readEscapedString(start: Int) throws -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(32)
        bytes.append(contentsOf: buffer[start ..< offset])

        while offset < buffer.count {
            let byte = buffer[offset]
            if byte == JSONByte.quote.rawValue {
                offset += 1
                return String(decoding: bytes, as: UTF8.self)
            }
            if byte == JSONByte.backslash.rawValue {
                offset += 1
                guard let escaped = peek() else {
                    throw _KomaJSONError.unexpectedEnd
                }
                offset += 1
                switch escaped {
                case JSONByte.quote.rawValue, JSONByte.backslash.rawValue, JSONByte.slash.rawValue:
                    bytes.append(escaped)
                case JSONByte.b.rawValue:
                    bytes.append(8)
                case JSONByte.f.rawValue:
                    bytes.append(12)
                case JSONByte.n.rawValue:
                    bytes.append(10)
                case JSONByte.r.rawValue:
                    bytes.append(13)
                case JSONByte.t.rawValue:
                    bytes.append(9)
                case JSONByte.u.rawValue:
                    let scalar = try readUnicodeEscape()
                    bytes.append(contentsOf: String(scalar).utf8)
                default:
                    throw _KomaJSONError.unsupportedEscape(offset: offset - 1)
                }
                continue
            }
            bytes.append(byte)
            offset += 1
        }

        throw _KomaJSONError.unexpectedEnd
    }

    mutating func readUnicodeEscape() throws -> UnicodeScalar {
        let first = try readHexValue()
        guard 0xD800 ... 0xDBFF ~= first else {
            guard let scalar = UnicodeScalar(first) else {
                throw _KomaJSONError.unsupportedEscape(offset: offset - 4)
            }
            return scalar
        }

        guard consumeIf(.backslash), consumeIf(.u) else {
            throw _KomaJSONError.unsupportedEscape(offset: offset)
        }
        let second = try readHexValue()
        guard 0xDC00 ... 0xDFFF ~= second else {
            throw _KomaJSONError.unsupportedEscape(offset: offset)
        }

        let high = first - 0xD800
        let low = second - 0xDC00
        let combined = 0x10000 + ((high << 10) | low)
        guard let scalar = UnicodeScalar(combined) else {
            throw _KomaJSONError.unsupportedEscape(offset: offset)
        }
        return scalar
    }

    mutating func readHexValue() throws -> UInt32 {
        guard offset + 4 <= buffer.count else {
            throw _KomaJSONError.unexpectedEnd
        }

        var value: UInt32 = 0
        for _ in 0 ..< 4 {
            let byte = buffer[offset]
            offset += 1
            value = try (value << 4) | UInt32(Self.hexValue(byte, offset: offset - 1))
        }

        return value
    }

    static func hexValue(_ byte: UInt8, offset: Int) throws -> UInt8 {
        switch byte {
        case 48 ... 57:
            return byte - 48
        case 65 ... 70:
            return byte - 55
        case 97 ... 102:
            return byte - 87
        default:
            throw _KomaJSONError.unsupportedEscape(offset: offset)
        }
    }
}
