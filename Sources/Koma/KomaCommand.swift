import Foundation

/// A write operation (typically `DELETE`) executed through Koma's HTTP layer — the same
/// plugin pipeline as `KomaFetch`, so auth, retry, and logging apply — that evicts local
/// store rows once the request succeeds. The write counterpart to a read `KomaFetch`
/// (CQRS: queries read, commands write).
///
/// Unlike `KomaFetch` (read → decode → `upsert`), a command does not decode a response
/// body into records. It performs the request and then removes the queued rows from the
/// local store, keeping the store consistent with a server-side delete.
///
/// A `DELETE` that returns `404 Not Found` is treated as success: the resource is already
/// gone, so the local rows are still evicted. This makes deletes idempotent and prevents a
/// stale cached row (one the server has already dropped) from resurfacing on the next
/// refresh. Set `notFoundIsSuccess` to `false` to opt out (e.g. for a `PUT`/`POST` where a
/// 404 is a real error).
///
/// ```swift
/// try await KomaCommand<OutfitRecord>(
///     client: koma,
///     operation: KomaOperation(
///         name: "deleteOutfit",
///         method: .delete,
///         path: "projects/{projectId}/characters/{characterId}/outfits/{outfitId}",
///         pathValues: ["projectId": projectId, "characterId": characterId, "outfitId": outfitId]
///     ),
///     evicting: [OutfitRecord.cacheId(projectId: projectId, characterId: characterId, outfitId: outfitId)]
/// ).perform()
/// ```
public struct KomaCommand<Record: KomaEntityRecord>: Sendable {
    let client: KomaClient
    let operation: KomaOperation
    let evictIds: [String]
    let notFoundIsSuccess: Bool

    public init(
        client: KomaClient,
        operation: KomaOperation,
        evicting evictIds: [String] = [],
        notFoundIsSuccess: Bool = true
    ) {
        self.client = client
        self.operation = operation
        self.evictIds = evictIds
        self.notFoundIsSuccess = notFoundIsSuccess
    }

    /// Sends the request through the client's plugin pipeline, then evicts the queued rows.
    ///
    /// - Returns: The HTTP response, or `nil` when a `404` was absorbed as success.
    @discardableResult
    public func perform() async throws -> KomaResponse? {
        try await client.store.ensureSchema(for: Record.self)

        var request = try KomaRequest(
            method: operation.method,
            path: operation.resolvedPath,
            queryItems: operation.queryItems,
            headers: ["Accept": "application/json"],
            body: operation.body?.data()
        )
        if request.body != nil {
            request.headers["Content-Type"] = "application/json"
        }

        var response: KomaResponse?
        do {
            response = try await client.execute(request, operation: operation.name)
        } catch let error as KomaHTTPError {
            guard notFoundIsSuccess, case let .invalidResponse(statusCode, _) = error, statusCode == 404 else {
                throw error
            }
            // Already gone server-side — fall through and evict so the local store matches.
            response = nil
        }

        for id in evictIds {
            try await client.store.delete(Record.self, id: id)
        }
        return response
    }
}
