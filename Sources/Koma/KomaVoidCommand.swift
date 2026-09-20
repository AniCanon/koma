import Foundation

/// A write executed through Koma's HTTP layer — the same plugin pipeline as `KomaFetch`, so
/// auth, retry, and logging apply — that neither decodes a response nor touches the store.
///
/// This is the third command shape. `KomaCommand` performs a write and evicts local rows, so
/// it is generic over the record it evicts; `KomaReturningCommand` performs a write and decodes
/// its response, so it is generic over that value. A write that answers `204 No Content` and
/// owns no local rows — a register, an unregister, a delete-account, a retry or discard — has
/// neither, so it names no type at all. Reaching for `KomaCommand` with `evicting: []` there
/// would force the caller to name a record the write never touches.
///
/// ```swift
/// try await KomaVoidCommand(
///     client: koma,
///     operation: KomaOperation(
///         name: "retryRender",
///         method: .post,
///         path: "projects/{projectId}/renders/{renderId}/retry",
///         pathValues: ["projectId": projectId, "renderId": renderId]
///     )
/// ).perform()
/// ```
///
/// A `404 Not Found` is treated as success, the same default as `KomaCommand`: the common void
/// write is an unregister or a delete whose 404 means the intent is already satisfied, so
/// absorbing it keeps the call idempotent. Set `notFoundIsSuccess` to `false` where a 404 is a
/// real error — a `POST` that retries or assembles something that must exist.
///
/// When the response does carry a value the caller needs, use `KomaReturningCommand`; when the
/// write invalidates local rows, use `KomaCommand`, which evicts them once the request succeeds.
public struct KomaVoidCommand: Sendable {
    let client: KomaClient
    let operation: KomaOperation
    let notFoundIsSuccess: Bool

    /// Creates a void command.
    ///
    /// - Parameters:
    ///   - client: The Koma client whose transport and plugins execute the request.
    ///   - operation: The concrete request to send.
    ///   - notFoundIsSuccess: Whether a `404` response is absorbed as success. Defaults to
    ///     `true`, matching `KomaCommand`, so an unregister or delete stays idempotent.
    public init(
        client: KomaClient,
        operation: KomaOperation,
        notFoundIsSuccess: Bool = true
    ) {
        self.client = client
        self.operation = operation
        self.notFoundIsSuccess = notFoundIsSuccess
    }

    /// Sends the request through the client's plugin pipeline.
    ///
    /// - Returns: The HTTP response, or `nil` when a `404` was absorbed as success.
    @discardableResult
    public func perform() async throws -> KomaResponse? {
        let request = try operation.makeRequest()

        do {
            return try await client.execute(request, operation: operation.name)
        } catch let error as KomaHTTPError {
            guard notFoundIsSuccess, case let .invalidResponse(statusCode, _) = error, statusCode == 404 else {
                throw error
            }
            // Already gone server-side — the write's intent is satisfied.
            return nil
        }
    }
}
