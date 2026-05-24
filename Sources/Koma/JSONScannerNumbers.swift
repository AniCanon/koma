extension _KomaJSONScanner {
    mutating func readInt64() throws -> Int64 {
        try skipWhitespace()
        let start = offset
        var sign: Int64 = 1
        if peek() == JSONByte.minus.rawValue {
            sign = -1
            offset += 1
        }

        var value: Int64 = 0
        var readDigit = false
        while let byte = peek(), byte >= 48, byte <= 57 {
            readDigit = true
            value = value * 10 + Int64(byte - 48)
            offset += 1
        }

        guard readDigit else {
            throw _KomaJSONError.invalidNumber(offset: start)
        }
        guard !isNumberContinuation(peek()) else {
            throw _KomaJSONError.invalidNumber(offset: start)
        }
        return value * sign
    }

    mutating func readNumberRange() throws -> Range<Int> {
        try skipWhitespace()
        let start = offset
        if peek() == JSONByte.minus.rawValue {
            offset += 1
        }

        var readDigit = false
        while let byte = peek(), byte >= 48, byte <= 57 {
            readDigit = true
            offset += 1
        }
        if peek() == JSONByte.period.rawValue {
            offset += 1
            while let byte = peek(), byte >= 48, byte <= 57 {
                readDigit = true
                offset += 1
            }
        }
        if let byte = peek(), byte == JSONByte.e.rawValue || byte == JSONByte.capitalE.rawValue {
            offset += 1
            if let sign = peek(), sign == JSONByte.plus.rawValue || sign == JSONByte.minus.rawValue {
                offset += 1
            }
            var readExponentDigit = false
            while let byte = peek(), byte >= 48, byte <= 57 {
                readExponentDigit = true
                offset += 1
            }
            guard readExponentDigit else {
                throw _KomaJSONError.invalidNumber(offset: start)
            }
        }

        guard readDigit else {
            throw _KomaJSONError.invalidNumber(offset: start)
        }
        return start ..< offset
    }

    func isNumberContinuation(_ byte: UInt8?) -> Bool {
        guard let byte else {
            return false
        }
        return byte == JSONByte.period.rawValue ||
            byte == JSONByte.e.rawValue ||
            byte == JSONByte.capitalE.rawValue
    }
}
