import Foundation

/// A write executed through Koma's HTTP layer — the same plugin pipeline as `KomaFetch`, so
/// auth, retry, and logging apply — whose response is decoded and returned to the caller.
///
/// Use this for the writes whose response is not stored data: a job handle, an analysis
/// payload, a presigned upload. `KomaCommand` performs a write and evicts local rows without
/// decoding a body; this is its returning form (CQRS: queries read, commands write, and a
/// command may still report what it produced). It needs no `Record` type because nothing is
/// persisted.
///
/// ```swift
/// let job: Job = try await KomaReturningCommand(
///     client: koma,
///     operation: KomaOperation(
///         name: "generateImage",
///         method: .post,
///         path: "projects/{projectId}/images",
///         pathValues: ["projectId": projectId],
///         body: KomaRequestBody { try JSONEncoder().encode(request) }
///     )
/// ).perform()
/// ```
///
/// The response must carry a JSON body the client's `jsonDecoder` can decode as `Value`. An
/// empty or `204` response has nothing to return — use `KomaCommand` for a write that evicts
/// local rows, or `KomaVoidCommand` for one that touches nothing locally. A non-2xx
/// status throws `KomaHTTPError.invalidResponse(statusCode:body:)` before any decoding is
/// attempted; `404` is a plain failure here, with no `notFoundIsSuccess` absorption.
///
/// When the response body does contain records worth keeping, do not decode it here — run
/// the operation through `KomaFetch` (a resource route, with an adapter if the shape is an
/// envelope) so the records are persisted once, by the persistence path that owns that work.
public struct KomaReturningCommand<Value: Decodable & Sendable>: Sendable {
    let client: KomaClient
    let operation: KomaOperation

    /// Creates a returning command.
    ///
    /// - Parameters:
    ///   - client: The Koma client whose transport, plugins, and decoder execute the request.
    ///   - operation: The concrete request to send.
    ///   - value: The decoded response type. Usually inferred from the call site.
    public init(
        client: KomaClient,
        operation: KomaOperation,
        value _: Value.Type = Value.self
    ) {
        self.client = client
        self.operation = operation
    }

    /// Sends the request through the client's plugin pipeline and decodes the response.
    ///
    /// - Returns: The decoded response value.
    public func perform() async throws -> Value {
        let request = try operation.makeRequest()
        let response = try await client.execute(request, operation: operation.name)
        return try client.jsonDecoder.decode(Value.self, from: response.body)
    }
}
