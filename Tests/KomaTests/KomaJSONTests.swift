import Foundation
import Koma
import KomaMacros
import Testing

@KomaEntity(table: "json_projects")
private struct JSONProjectRecord: KomaEntityRecord, Equatable {
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
private struct JSONFastPathProfileRecord: KomaEntityRecord, Equatable {
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

struct KomaJSONTests {
    @Test
    func `JSON record path decodes empty arrays and single objects`() throws {
        let empty = try JSONProjectRecord._komaJSONRecords(from: Data("[]".utf8))
        #expect(empty.isEmpty)

        let object = try JSONProjectRecord._komaJSONRecord(
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

        let records = try JSONProjectRecord._komaJSONRecords(from: body)

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

        let records = try JSONFastPathProfileRecord._komaJSONRecords(from: body)

        #expect(JSONFastPathProfileRecord._komaJSONFastPath)
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
    func `JSON record path reports missing required fields`() throws {
        let body = Data(#"[{"id":"1","rank":1}]"#.utf8)

        do {
            _ = try JSONProjectRecord._komaJSONRecords(from: body)
            Issue.record("Expected missing required field error.")
        } catch {
            #expect(error as? _KomaJSONError == .missingRequiredField("name"))
        }
    }

    @Test
    func `JSON record path rejects invalid escapes and malformed numbers`() throws {
        let invalidEscape = Data(#"[{"id":"1","name":"\uD800","rank":1}]"#.utf8)
        do {
            _ = try JSONProjectRecord._komaJSONRecords(from: invalidEscape)
            Issue.record("Expected unsupported escape error.")
        } catch _KomaJSONError.unsupportedEscape {
        } catch {
            Issue.record("Expected unsupported escape, got \(error).")
        }

        let malformedInteger = Data(#"[{"id":"1","name":"Alpha","rank":1.2}]"#.utf8)
        do {
            _ = try JSONProjectRecord._komaJSONRecords(from: malformedInteger)
            Issue.record("Expected invalid number error.")
        } catch _KomaJSONError.invalidNumber {
        } catch {
            Issue.record("Expected invalid number, got \(error).")
        }
    }
}
