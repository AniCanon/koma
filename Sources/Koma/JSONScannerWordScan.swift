extension KomaJSONScanner {
    /// Bytes processed per word by the SWAR (SIMD-within-a-register) delimiter scan.
    @usableFromInline
    static let wordStride = 8

    /// Branch-free test for whether any byte lane of `word` equals `byte`.
    ///
    /// XOR-ing the replicated target into the word turns every matching lane into 0x00,
    /// and the classic "has a zero byte" bit trick detects it without inspecting lanes one
    /// at a time. The test is exact — no false positives — so callers can rely on it to
    /// gate a precise scalar scan.
    @inline(__always)
    static func wordContains(_ word: UInt64, _ byte: UInt8) -> Bool {
        let matched = word ^ (UInt64(byte) &* 0x0101_0101_0101_0101)
        return (matched &- 0x0101_0101_0101_0101) & ~matched & 0x8080_8080_8080_8080 != 0
    }

    /// High bit of every byte lane, used to detect non-ASCII content.
    @usableFromInline
    static let highBits: UInt64 = 0x8080_8080_8080_8080

    /// Advances `offset` to the first quote or backslash at/after the current offset and
    /// returns that byte plus whether every body byte scanned was ASCII (`< 0x80`). Throws
    /// if the buffer ends first.
    ///
    /// Whole 8-byte words free of both delimiters are skipped at once via SWAR; the scalar
    /// tail then identifies the exact stopping byte. Quote (34) and backslash (92) are
    /// < 0x80, so they never appear inside a multibyte UTF-8 sequence and the word skip
    /// cannot overrun one. The ASCII flag lets `readString` skip UTF-8 validation when it is
    /// provably unnecessary, while non-ASCII content still flows through the validating path.
    ///
    /// SWAR is used instead of `SIMD16` here because Swift's `SIMDMask` reductions
    /// (`any`/`all`) do not lower to a hardware movemask on the supported targets and
    /// measured ~4-13x slower than this integer-only path on short tokens.
    @inline(__always)
    mutating func skipToStringDelimiter() throws -> (delimiter: UInt8, isASCII: Bool) {
        var nonASCII = false
        if let base = buffer.baseAddress {
            var index = offset
            let limit = buffer.count - Self.wordStride
            var seenBits: UInt64 = 0
            while index <= limit {
                let word = UnsafeRawPointer(base + index).loadUnaligned(as: UInt64.self)
                if Self.wordContains(word, JSONByte.quote.rawValue)
                    || Self.wordContains(word, JSONByte.backslash.rawValue)
                {
                    break
                }
                seenBits |= word
                index += Self.wordStride
            }
            nonASCII = seenBits & Self.highBits != 0
            offset = index
        }

        while offset < buffer.count {
            let byte = buffer[offset]
            if byte == JSONByte.quote.rawValue || byte == JSONByte.backslash.rawValue {
                return (byte, !nonASCII)
            }
            if byte & 0x80 != 0 {
                nonASCII = true
            }
            offset += 1
        }

        throw KomaJSONFastPathError.unexpectedEnd
    }

    /// Builds a `String` from `buffer[start ..< end]` without re-validating UTF-8.
    ///
    /// Only safe when the caller has already established that the range is pure ASCII (and
    /// therefore trivially valid UTF-8); non-ASCII content must use `String(decoding:as:)`
    /// so malformed sequences are still repaired to U+FFFD.
    @inline(__always)
    func makeASCIIString(start: Int, end: Int) -> String {
        let count = end - start
        guard count > 0, let base = buffer.baseAddress else {
            return ""
        }
        // Tripwire: independently re-verify the caller's ASCII claim. Compiled out in
        // release, so the fast path keeps its cost, but a future mis-tracking of `isASCII`
        // fails loudly in tests instead of silently producing a malformed String.
        assert(
            (start ..< end).allSatisfy { buffer[$0] & 0x80 == 0 },
            "makeASCIIString requires pure-ASCII bytes; isASCII tracking is broken"
        )
        return String(unsafeUninitializedCapacity: count) { destination in
            destination.baseAddress!.initialize(from: base + start, count: count)
            return count
        }
    }
}
