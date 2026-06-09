import Foundation
import Koma
import Testing

@KomaEntity(table: "json_projects")
struct JSONProjectRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var name: String
    var rank: Int
    var deletedAt: Date?

    init(id: String, name: String, rank: Int, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.rank = rank
        self.deletedAt = deletedAt
    }
}

@KomaEntity(table: "json_fast_path_profiles")
struct JSONFastPathProfileRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var title: String
    var nickname: String?
    var publishedAt: Date?

    init(id: String, title: String, nickname: String? = nil, publishedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.nickname = nickname
        self.publishedAt = publishedAt
    }
}

@KomaEntity(table: "json_common_scalars")
struct JSONCommonScalarRecord: KomaEntityRecord, Equatable {
    @KomaPrimaryKey var id: String
    var isActive: Bool
    var visits: Int64
    var rating: Double
    var progress: Float
    var createdAt: Date
    var nickname: String?

    init(
        id: String,
        isActive: Bool,
        visits: Int64,
        rating: Double,
        progress: Float,
        createdAt: Date,
        nickname: String? = nil
    ) {
        self.id = id
        self.isActive = isActive
        self.visits = visits
        self.rating = rating
        self.progress = progress
        self.createdAt = createdAt
        self.nickname = nickname
    }
}

struct KomaJSONTests {
    @Test
    func `JSON record path decodes empty arrays and single objects`() throws {
        let empty = try JSONProjectRecord.komaJSONRecords(from: Data("[]".utf8))
        #expect(empty.isEmpty)

        let object = try JSONProjectRecord.komaJSONRecord(
            from: Data(#"{"id":"1","name":"Alpha","rank":7,"deletedAt":123.25}"#.utf8)
        )

        #expect(object == JSONProjectRecord(id: "1", name: "Alpha", rank: 7, deletedAt: Date(timeIntervalSinceReferenceDate: 123.25)))
    }

    @Test
    func `JSON record path skips nested unknown values`() throws {
        let body = Data(
            """
            [{
              "id": "1",
              "name": "Alpha",
              "rank": 1,
              "deletedAt": null,
              "metadata": {
                "flags": [true, false, null, {"nested": "value"}],
                "score": 1.5
              }
            }]
            """.utf8
        )

        let records = try JSONProjectRecord.komaJSONRecords(from: body)

        #expect(records == [JSONProjectRecord(id: "1", name: "Alpha", rank: 1)])
    }

    @Test
    func `JSON record path decodes optional null string and date fields`() throws {
        let body = Data(
            """
            [
              {
                "id": "1",
                "title": "Alpha",
                "nickname": null,
                "publishedAt": null
              },
              {
                "id": "2",
                "title": "Beta",
                "nickname": "Bee",
                "publishedAt": 456.75
              }
            ]
            """.utf8
        )

        let records = try JSONFastPathProfileRecord.komaJSONRecords(from: body)

        #expect(JSONFastPathProfileRecord.komaUsesJSONFastPath)
        #expect(records == [
            JSONFastPathProfileRecord(id: "1", title: "Alpha"),
            JSONFastPathProfileRecord(
                id: "2",
                title: "Beta",
                nickname: "Bee",
                publishedAt: Date(timeIntervalSinceReferenceDate: 456.75)
            )
        ])
    }

    @Test
    func `JSON record path round trips common scalar fields`() throws {
        let record = JSONCommonScalarRecord(
            id: "scalar-1",
            isActive: true,
            visits: 9_223_372_036,
            rating: 4.5,
            progress: 0.25,
            createdAt: Date(timeIntervalSinceReferenceDate: 789.5),
            nickname: "A\nB"
        )

        let body = try record.komaJSONData()
        let decoded = try JSONCommonScalarRecord.komaJSONRecord(from: body)

        #expect(decoded == record)
        #expect(String(data: body, encoding: .utf8)?.contains(#""createdAt":789.5"#) == true)
        #expect(String(data: body, encoding: .utf8)?.contains(#""isActive":true"#) == true)
        #expect(String(data: body, encoding: .utf8)?.contains(#""nickname":"A\nB""#) == true)
    }

    @Test
    func `JSON record path escapes every string class and round trips`() throws {
        // Quotes, backslashes, the named control escapes, an arbitrary control byte, multi-byte
        // UTF-8, and runs longer than the writer's 8-byte word stride with escapes at varying
        // offsets so word-boundary handling is exercised.
        let nicknames = [
            "say \"hi\" \\ done",
            "\u{08}\u{0C}\n\r\t\u{01}\u{1F}",
            "héllo 日本語 🚀 plain tail",
            String(repeating: "a", count: 23) + "\"" + String(repeating: "b", count: 9),
            "\"leading and trailing\""
        ]

        for nickname in nicknames {
            let record = JSONCommonScalarRecord(
                id: "escape",
                isActive: false,
                visits: 1,
                rating: 1,
                progress: 1,
                createdAt: Date(timeIntervalSinceReferenceDate: 0),
                nickname: nickname
            )

            let body = try record.komaJSONData()
            #expect(try JSONCommonScalarRecord.komaJSONRecord(from: body) == record)

            // Cross-validate against Foundation so a writer bug can't be masked by a
            // matching scanner bug.
            let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
            #expect(object?["nickname"] as? String == nickname)
        }
    }

    @Test
    func `JSON record path round trips integer extremes`() throws {
        for visits in [Int64.max, Int64.min, -1, 0, 42] {
            let record = JSONCommonScalarRecord(
                id: "extremes",
                isActive: false,
                visits: visits,
                rating: 1,
                progress: 1,
                createdAt: Date(timeIntervalSinceReferenceDate: 0),
                nickname: nil
            )

            let body = try record.komaJSONData()
            #expect(try JSONCommonScalarRecord.komaJSONRecord(from: body) == record)
        }
        let body = try JSONCommonScalarRecord(
            id: "extremes",
            isActive: false,
            visits: Int64.min,
            rating: 1,
            progress: 1,
            createdAt: Date(timeIntervalSinceReferenceDate: 0),
            nickname: nil
        ).komaJSONData()
        #expect(String(data: body, encoding: .utf8)?.contains("\"visits\":-9223372036854775808") == true)
    }

    @Test
    func `JSON record path throws on integer overflow instead of trapping`() throws {
        for visits in ["9223372036854775808", "-9223372036854775809", "99999999999999999999999"] {
            let body = Data(
                #"{"id":"x","isActive":true,"visits":\#(visits),"rating":1,"progress":1,"createdAt":0}"#.utf8
            )
            #expect(throws: (any Error).self) {
                try JSONCommonScalarRecord.komaJSONRecord(from: body)
            }
        }
    }

    @Test
    func `JSON record path falls back for high precision doubles`() throws {
        let body = Data(
            #"{"id":"scalar-1","isActive":true,"visits":1,"rating":0.123456789012345678901,"progress":0.25,"createdAt":789.5}"#.utf8
        )

        let decoded = try JSONCommonScalarRecord.komaJSONRecord(from: body)

        #expect(decoded.rating == Double("0.123456789012345678901"))
    }

    @Test
    func `JSON record path rejects ISO dates so configured decoders can own that strategy`() throws {
        let body = Data(
            #"[{"id":"1","name":"Alpha","rank":1,"deletedAt":"2026-01-02T03:04:05Z"}]"#.utf8
        )

        do {
            _ = try JSONProjectRecord.komaJSONRecords(from: body)
            Issue.record("Expected fast JSON path to reject ISO date strings.")
        } catch is KomaJSONFastPathError {
        } catch {
            Issue.record("Expected Koma JSON error, got \(error).")
        }
    }

    @Test
    func `JSON record path reports missing required fields`() throws {
        let body = Data(#"[{"id":"1","rank":1}]"#.utf8)

        do {
            _ = try JSONProjectRecord.komaJSONRecords(from: body)
            Issue.record("Expected missing required field error.")
        } catch {
            #expect(error as? KomaJSONFastPathError == .missingRequiredField("name"))
        }
    }

    @Test
    func `JSON record path rejects invalid escapes and malformed numbers`() throws {
        let invalidEscape = Data(#"[{"id":"1","name":"\uD800","rank":1}]"#.utf8)
        do {
            _ = try JSONProjectRecord.komaJSONRecords(from: invalidEscape)
            Issue.record("Expected unsupported escape error.")
        } catch KomaJSONFastPathError.unsupportedEscape {
        } catch {
            Issue.record("Expected unsupported escape, got \(error).")
        }

        let malformedInteger = Data(#"[{"id":"1","name":"Alpha","rank":1.2}]"#.utf8)
        do {
            _ = try JSONProjectRecord.komaJSONRecords(from: malformedInteger)
            Issue.record("Expected invalid number error.")
        } catch KomaJSONFastPathError.invalidNumber {
        } catch {
            Issue.record("Expected invalid number, got \(error).")
        }
    }
}
