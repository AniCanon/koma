import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

struct KomaConditionalRequestTests {
    private func makeStore() async throws -> SQLiteKomaStore {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("koma-conditional-\(UUID().uuidString).sqlite").path
        return try await SQLiteKomaStore(path: path)
    }

    private func makeClient(
        transport: FakeKomaTransport,
        store: SQLiteKomaStore,
        conditionalRequests: KomaConditionalRequests = .automatic
    ) throws -> KomaClient {
        try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport,
            jsonOptimization: .automatic,
            conditionalRequests: conditionalRequests
        )
    }

    private let listBody = Data(#"[{"id":"1","name":"Alpha","slug":"alpha"}]"#.utf8)

    @Test
    func `revalidation sends If-None-Match and serves a 304 from the local store`() async throws {
        let store = try await makeStore()
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, headers: ["ETag": "\"v1\""], body: listBody),
            KomaResponse(statusCode: 304, body: Data())
        ])
        let koma = try makeClient(transport: transport, store: store)
        let resource = ProjectResources.client(in: koma)

        let first = try await resource.list().fetch(policy: .networkFirstFallback)
        #expect(first.value.map(\.id) == ["1"])

        let second = try await resource.list().fetch(policy: .networkFirstFallback)
        #expect(second.value.map(\.id) == ["1"])
        #expect(second.source == .network)

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].headers["If-None-Match"] == nil)
        #expect(requests[1].headers["If-None-Match"] == "\"v1\"")
    }

    @Test
    func `changed content updates the stored validator`() async throws {
        let store = try await makeStore()
        let renamedBody = Data(#"[{"id":"1","name":"Alpha Prime","slug":"alpha"}]"#.utf8)
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, headers: ["ETag": "\"v1\""], body: listBody),
            KomaResponse(statusCode: 200, headers: ["ETag": "\"v2\""], body: renamedBody),
            KomaResponse(statusCode: 304, body: Data())
        ])
        let koma = try makeClient(transport: transport, store: store)
        let resource = ProjectResources.client(in: koma)

        _ = try await resource.list().fetch(policy: .networkFirstFallback)
        let second = try await resource.list().fetch(policy: .networkFirstFallback)
        #expect(second.value.map(\.name) == ["Alpha Prime"])

        let third = try await resource.list().fetch(policy: .networkFirstFallback)
        #expect(third.value.map(\.name) == ["Alpha Prime"])

        let requests = await transport.requests
        #expect(requests.count == 3)
        #expect(requests[1].headers["If-None-Match"] == "\"v1\"")
        #expect(requests[2].headers["If-None-Match"] == "\"v2\"")
    }

    @Test
    func `refresh returns local output on 304`() async throws {
        let store = try await makeStore()
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, headers: ["ETag": "\"v1\""], body: listBody),
            KomaResponse(statusCode: 304, body: Data())
        ])
        let koma = try makeClient(transport: transport, store: store)
        let resource = ProjectResources.client(in: koma)

        _ = try await resource.list().refresh()
        let revalidated = try await resource.list().refresh()
        #expect(revalidated.map(\.id) == ["1"])
    }

    @Test
    func `servers without validators never trigger conditional headers`() async throws {
        let store = try await makeStore()
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, body: listBody),
            KomaResponse(statusCode: 200, body: listBody)
        ])
        let koma = try makeClient(transport: transport, store: store)
        let resource = ProjectResources.client(in: koma)

        _ = try await resource.list().fetch(policy: .networkFirstFallback)
        _ = try await resource.list().fetch(policy: .networkFirstFallback)

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[1].headers["If-None-Match"] == nil)
        #expect(requests[1].headers["If-Modified-Since"] == nil)
    }

    @Test
    func `disabled mode stores no validators and sends no conditional headers`() async throws {
        let store = try await makeStore()
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, headers: ["ETag": "\"v1\""], body: listBody),
            KomaResponse(statusCode: 200, headers: ["ETag": "\"v1\""], body: listBody)
        ])
        let koma = try makeClient(transport: transport, store: store, conditionalRequests: .disabled)
        let resource = ProjectResources.client(in: koma)

        _ = try await resource.list().fetch(policy: .networkFirstFallback)
        _ = try await resource.list().fetch(policy: .networkFirstFallback)

        let requests = await transport.requests
        #expect(requests[1].headers["If-None-Match"] == nil)

        let validators = try await store.query(KomaHTTPValidatorRecord.self).fetch()
        #expect(validators.isEmpty)
    }
}
