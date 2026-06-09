extension KomaJSONScanner {
    mutating func readInt64() throws -> Int64 {
        try skipWhitespace()
        let start = offset
        var sign: Int64 = 1
        if peek() == JSONByte.minus.rawValue {
            sign = -1
            offset += 1
        }

        // Accumulate the magnitude with overflow-checked arithmetic: unchecked `value * 10`
        // would TRAP on oversized input (a crash reachable from attacker-controlled payloads),
        // and Int64.min has no positive Int64 counterpart.
        var magnitude: UInt64 = 0
        var readDigit = false
        while offset < buffer.count {
            let byte = buffer[offset]
            guard byte >= 48, byte <= 57 else {
                break
            }
            readDigit = true
            let (scaled, multiplyOverflowed) = magnitude.multipliedReportingOverflow(by: 10)
            let (next, addOverflowed) = scaled.addingReportingOverflow(UInt64(byte - 48))
            guard !multiplyOverflowed, !addOverflowed else {
                throw KomaJSONFastPathError.integerOverflow("Int64")
            }
            magnitude = next
            offset += 1
        }

        guard readDigit else {
            throw KomaJSONFastPathError.invalidNumber(offset: start)
        }
        guard !isNumberContinuation(peek()) else {
            throw KomaJSONFastPathError.invalidNumber(offset: start)
        }
        if sign < 0 {
            guard magnitude <= UInt64(Int64.max) + 1 else {
                throw KomaJSONFastPathError.integerOverflow("Int64")
            }
            return magnitude == UInt64(Int64.max) + 1 ? Int64.min : 0 &- Int64(magnitude)
        }
        guard magnitude <= UInt64(Int64.max) else {
            throw KomaJSONFastPathError.integerOverflow("Int64")
        }
        return Int64(magnitude)
    }

    mutating func readNumberRange() throws -> Range<Int> {
        try skipWhitespace()
        let start = offset
        if peek() == JSONByte.minus.rawValue {
            offset += 1
        }

        var readDigit = false
        while offset < buffer.count {
            let byte = buffer[offset]
            guard byte >= 48, byte <= 57 else {
                break
            }
            readDigit = true
            offset += 1
        }
        if peek() == JSONByte.period.rawValue {
            offset += 1
            while offset < buffer.count {
                let byte = buffer[offset]
                guard byte >= 48, byte <= 57 else {
                    break
                }
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
            while offset < buffer.count {
                let byte = buffer[offset]
                guard byte >= 48, byte <= 57 else {
                    break
                }
                readExponentDigit = true
                offset += 1
            }
            guard readExponentDigit else {
                throw KomaJSONFastPathError.invalidNumber(offset: start)
            }
        }

        guard readDigit else {
            throw KomaJSONFastPathError.invalidNumber(offset: start)
        }
        return start ..< offset
    }

    mutating func readDoubleValue() throws -> Double {
        try skipWhitespace()
        let start = offset
        var isNegative = false
        if peek() == JSONByte.minus.rawValue {
            isNegative = true
            offset += 1
        }

        var mantissa: UInt64 = 0
        var mantissaDigits = 0
        var decimalExponent = 0
        var droppedSignificantDigits = false

        func appendDigit(_ digit: UInt8, isInteger: Bool) {
            if mantissaDigits == 0, digit == 0 {
                if !isInteger {
                    decimalExponent -= 1
                }
                return
            }

            guard mantissaDigits < 18 else {
                droppedSignificantDigits = true
                if isInteger {
                    decimalExponent += 1
                }
                return
            }

            mantissa = mantissa * 10 + UInt64(digit)
            mantissaDigits += 1
            if !isInteger {
                decimalExponent -= 1
            }
        }

        var readIntegerDigit = false
        while offset < buffer.count {
            let byte = buffer[offset]
            guard byte >= 48, byte <= 57 else {
                break
            }
            readIntegerDigit = true
            appendDigit(byte - 48, isInteger: true)
            offset += 1
        }

        if peek() == JSONByte.period.rawValue {
            offset += 1
            var readFractionDigit = false
            while offset < buffer.count {
                let byte = buffer[offset]
                guard byte >= 48, byte <= 57 else {
                    break
                }
                readFractionDigit = true
                appendDigit(byte - 48, isInteger: false)
                offset += 1
            }
            guard readFractionDigit else {
                throw KomaJSONFastPathError.invalidNumber(offset: start)
            }
        }

        guard readIntegerDigit else {
            throw KomaJSONFastPathError.invalidNumber(offset: start)
        }

        if let byte = peek(), byte == JSONByte.e.rawValue || byte == JSONByte.capitalE.rawValue {
            offset += 1
            var exponentSign = 1
            if let sign = peek(), sign == JSONByte.plus.rawValue || sign == JSONByte.minus.rawValue {
                exponentSign = sign == JSONByte.minus.rawValue ? -1 : 1
                offset += 1
            }

            var exponent = 0
            var readExponentDigit = false
            while offset < buffer.count {
                let byte = buffer[offset]
                guard byte >= 48, byte <= 57 else {
                    break
                }
                readExponentDigit = true
                if exponent < 10000 {
                    exponent = exponent * 10 + Int(byte - 48)
                }
                offset += 1
            }
            guard readExponentDigit else {
                throw KomaJSONFastPathError.invalidNumber(offset: start)
            }
            decimalExponent += exponentSign * exponent
        }

        guard mantissaDigits > 0 else {
            return isNegative ? -0.0 : 0.0
        }

        guard !droppedSignificantDigits, decimalExponent >= -22, decimalExponent <= 22 else {
            return try readDoubleWithFoundationFallback(start: start, end: offset)
        }

        var value = Double(mantissa)
        if decimalExponent > 0 {
            for _ in 0 ..< decimalExponent {
                value *= 10
            }
        } else if decimalExponent < 0 {
            for _ in 0 ..< -decimalExponent {
                value /= 10
            }
        }

        return isNegative ? -value : value
    }

    private func readDoubleWithFoundationFallback(start: Int, end: Int) throws -> Double {
        let literal = String(decoding: buffer[start ..< end], as: UTF8.self)
        guard let value = Double(literal) else {
            throw KomaJSONFastPathError.invalidNumber(offset: start)
        }
        return value
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
