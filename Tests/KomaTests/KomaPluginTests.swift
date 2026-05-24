import Foundation
import Koma
import KomaSQLite
import KomaTesting
import Testing

struct KomaPluginTests {
    @Test
    func `plugin prepare transforms are applied in order`() async throws {
        let store = try await makeStore()
        let transport = FakeKomaTransport(responses: [
            KomaResponse(statusCode: 200, body: Data(#"{"ok":true}"#.utf8))
        ])
        let koma = try KomaClient(
            baseURL: #require(URL(string: "https://example.com/v1")),
            store: store,
            transport: transport,
            plugins: [
                AppendHeaderPlugin(name: "X-Trace", value: "one"),
                RewriteRequestPlugin(),
                AppendHeaderPlugin(name: "X-Final", value: "done")
            ]
        )

        let original = KomaRequest(
            method: .post,
            path: "projects",
            queryItems: [URLQueryItem(name: "search", value: "alpha")],
            headers: ["X-Original": "kept"],
            body: Data("original".utf8)
        )

        _ = try await koma.execute(original, operation: "plugin-transform")

        let request = try #require(await transport.requests.first)
        #expect(request.method == .patch)
        #expect(request.path == "v2/projects")
        #expect(request.queryItems == [
            URLQueryItem(name: "search", value: "alpha"),
            URLQueryItem(name: "plugin", value: "rewrite")
        ])
        #expect(request.headers["X-Original"] == "kept")
        #expect(request.headers["X-Trace"] == "one")
        #expect(request.headers["X-Rewrite-Saw-Trace"] == "one")
        #expect(request.headers["X-Final"] == "done")
        #expect(request.body == Data("rewritten".utf8))
    }

    private func makeStore() async throws -> SQLiteKomaStore {
        try await SQLiteKomaStore(path: makeStorePath())
    }

    private func makeStorePath() -> String {
        FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("sqlite")
            .path
    }
}

private struct AppendHeaderPlugin: KomaHTTPPlugin {
    let name: String
    let value: String

    func prepare(_ request: consuming KomaRequest, context: KomaRequestContext) async throws -> KomaRequest {
        var request = request
        request.headers[name] = value
        return request
    }
}

private struct RewriteRequestPlugin: KomaHTTPPlugin {
    func prepare(_ request: consuming KomaRequest, context: KomaRequestContext) async throws -> KomaRequest {
        var request = request
        request.method = .patch
        request.path = "v2/\(request.path)"
        request.queryItems.append(URLQueryItem(name: "plugin", value: "rewrite"))
        request.headers["X-Rewrite-Saw-Trace"] = request.headers["X-Trace"]
        request.body = Data("rewritten".utf8)
        return request
    }
}
