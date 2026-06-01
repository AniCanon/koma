import Foundation
import Koma
import KomaMacros
import Testing

/// Boundary coverage for the JSON scanner hot loops (whitespace skipping, string-body
/// scanning, number parsing). The string scan skips whole machine words at a time (8-byte
/// SWAR), so these sweeps land a special byte (quote, backslash) or a multibyte UTF-8
/// sequence at every position relative to an 8- and 16-byte word boundary. They passed
/// against the scalar scanner and must keep passing after the word-scan rework.
struct KomaJSONScannerBoundaryTests {
    private func projectJSON(name: String, rank: Int = 1) -> Data {
        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return Data(#"{"id":"1","name":"\#(escaped)","rank":\#(rank)}"#.utf8)
    }

    @Test(arguments: 0 ... 40)
    func `string body of every length around the 16-byte stride decodes intact`(length: Int) throws {
        let name = String(repeating: "a", count: length)
        let decoded = try JSONProjectRecord.komaJSONRecord(from: projectJSON(name: name))
        #expect(JSONProjectRecord.komaUsesJSONFastPath)
        #expect(decoded.name == name)
    }

    @Test(arguments: 0 ... 34)
    func `escaped newline at every offset across a chunk boundary decodes intact`(prefix: Int) throws {
        // Backslash lands at body offset `prefix`; sweep places it at every lane.
        let name = String(repeating: "a", count: prefix) + "\n" + "b"
        let decoded = try JSONProjectRecord.komaJSONRecord(from: projectJSON(name: name))
        #expect(decoded.name == name)
    }

    @Test(arguments: 0 ... 34)
    func `escaped quote at every offset across a chunk boundary decodes intact`(prefix: Int) throws {
        let name = String(repeating: "a", count: prefix) + "\"" + "b"
        let decoded = try JSONProjectRecord.komaJSONRecord(from: projectJSON(name: name))
        #expect(decoded.name == name)
    }

    @Test(arguments: 0 ... 34)
    func `multibyte UTF-8 straddling a chunk boundary decodes intact`(prefix: Int) throws {
        // The emoji is 4 UTF-8 bytes; sweeping the prefix makes it cross a word boundary at some point.
        let name = String(repeating: "a", count: prefix) + "😀" + "z"
        let decoded = try JSONProjectRecord.komaJSONRecord(from: projectJSON(name: name))
        #expect(decoded.name == name)
    }

    @Test
    func `empty string decodes to empty`() throws {
        let decoded = try JSONProjectRecord.komaJSONRecord(from: projectJSON(name: ""))
        #expect(decoded.name.isEmpty)
    }

    @Test(arguments: [0, 1, 14, 15, 16, 17, 31, 32, 33, 48])
    func `whitespace runs of every length between tokens are skipped`(count: Int) throws {
        let ws = String(repeating: " ", count: count)
        let body = Data(
            "[\(ws){\(ws)\"id\"\(ws):\(ws)\"1\",\(ws)\"name\":\"Alpha\",\(ws)\"rank\":\(ws)1\(ws)}\(ws)]".utf8
        )
        let records = try JSONProjectRecord.komaJSONRecords(from: body)
        #expect(records == [JSONProjectRecord(id: "1", name: "Alpha", rank: 1)])
    }

    @Test(arguments: [0, 15, 16, 17, 32, 33])
    func `mixed whitespace bytes of every length are skipped`(count: Int) throws {
        // Cycle through space, tab, newline, carriage return.
        let bytes: [Character] = [" ", "\t", "\n", "\r"]
        let ws = String((0 ..< count).map { bytes[$0 % bytes.count] })
        let body = Data("\(ws)[{\"id\":\"1\",\"name\":\"Alpha\",\"rank\":1}]\(ws)".utf8)
        let records = try JSONProjectRecord.komaJSONRecords(from: body)
        #expect(records == [JSONProjectRecord(id: "1", name: "Alpha", rank: 1)])
    }

    @Test
    func `long digit run and number at end of buffer parse`() throws {
        // visits is Int64; rating/progress are floating point; no trailing whitespace so the
        // final number butts against end-of-buffer.
        let body = Data(
            #"{"id":"1","isActive":true,"visits":9223372036854775807,"rating":123456.7890123,"progress":0.5,"createdAt":1000000000.25}"#
                .utf8
        )
        let decoded = try JSONCommonScalarRecord.komaJSONRecord(from: body)
        #expect(decoded.visits == 9_223_372_036_854_775_807)
        #expect(decoded.rating == 123_456.7890123)
        #expect(decoded.createdAt == Date(timeIntervalSinceReferenceDate: 1_000_000_000.25))
    }

    @Test(arguments: [-123, 0, 7, 1000, 2_147_483_647])
    func `signed integers round trip across the digit-scan loop`(rank: Int) throws {
        let decoded = try JSONProjectRecord.komaJSONRecord(from: projectJSON(name: "Alpha", rank: rank))
        #expect(decoded.rank == rank)
    }
}
