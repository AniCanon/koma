import Foundation
import Koma
import KomaMacros
import Testing

private enum JSONProbeEncodingError: Error, Equatable {
    case failed
}

@KomaEntity(table: "json_probe_records")
private struct JSONProbeRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
    }

    func encode(to encoder: Encoder) throws {
        throw JSONProbeEncodingError.failed
    }
}

struct KomaJSONEncodingTests {
    @Test
    func `JSON record path encodes single objects and arrays`() throws {
        let records = [
            JSONProjectRecord(
                id: "1",
                name: "Quote \" slash \\ newline \n",
                rank: 7,
                deletedAt: Date(timeIntervalSinceReferenceDate: 123.25)
            ),
            JSONProjectRecord(id: "2", name: "Beta", rank: 8)
        ]

        let body = try JSONProjectRecord.komaJSONData(records: records)
        let decoded = try JSONProjectRecord.komaJSONRecords(from: body)

        #expect(decoded == records)
        #expect(String(data: body, encoding: .utf8)?.contains(#""deletedAt":"#) == true)
        #expect(String(data: body, encoding: .utf8)?.contains(#""id":"2","name":"Beta","rank":8}"#) == true)
    }

    @Test
    func `JSON record path can encode request bodies`() throws {
        let record = JSONProjectRecord(id: "1", name: "Alpha", rank: 7)

        let body = try KomaQueryEncoder.bodyData(from: record)

        #expect(String(data: body, encoding: .utf8) == #"{"id":"1","name":"Alpha","rank":7}"#)
    }

    @Test
    func `JSON record path can encode request body arrays`() throws {
        let records = [
            JSONProjectRecord(id: "1", name: "Alpha", rank: 7),
            JSONProjectRecord(id: "2", name: "Beta", rank: 8)
        ]

        let body = try KomaQueryEncoder.bodyData(from: records)

        #expect(String(data: body, encoding: .utf8) == #"[{"id":"1","name":"Alpha","rank":7},{"id":"2","name":"Beta","rank":8}]"#)
    }

    @Test
    func `request body JSON optimization can be disabled`() throws {
        let record = JSONProbeRecord(id: "1", name: "Alpha")

        let fastBody = try KomaQueryEncoder.bodyData(from: record, optimization: .automatic)
        #expect(String(data: fastBody, encoding: .utf8) == #"{"id":"1","name":"Alpha"}"#)

        do {
            _ = try KomaQueryEncoder.bodyData(from: record, optimization: .disabled)
            Issue.record("Expected disabled JSON optimization to use the configured encoder.")
        } catch JSONProbeEncodingError.failed {
        } catch {
            Issue.record("Expected JSONProbeEncodingError.failed, got \(error).")
        }
    }

    @Test
    func `request body encoding preserves configured ISO date strategy`() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-01-02T03:04:05Z"))
        let record = JSONProjectRecord(id: "1", name: "Alpha", rank: 7, deletedAt: date)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let body = try KomaQueryEncoder.bodyData(from: record, encoder: encoder)

        #expect(String(data: body, encoding: .utf8)?.contains(#""deletedAt":"2026-01-02T03:04:05Z""#) == true)
    }

    @Test
    func `request body encoding preserves configured key strategy`() throws {
        let record = JSONFastPathProfileRecord(
            id: "1",
            title: "Alpha",
            publishedAt: Date(timeIntervalSinceReferenceDate: 123.25)
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        let body = try KomaQueryEncoder.bodyData(from: record, encoder: encoder)

        #expect(String(data: body, encoding: .utf8)?.contains(#""published_at":"#) == true)
    }

    @Test
    func `JSON record path rejects non finite numbers`() throws {
        let record = JSONCommonScalarRecord(
            id: "scalar-1",
            isActive: true,
            visits: 1,
            rating: .infinity,
            progress: 0.25,
            createdAt: Date(timeIntervalSinceReferenceDate: 1)
        )

        do {
            _ = try record.komaJSONData()
            Issue.record("Expected non-finite number error.")
        } catch {
            #expect(error as? KomaJSONFastPathError == .nonFiniteNumber)
        }
    }
}
