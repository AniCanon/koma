import Foundation

/// A lazy delete operation that executes only when `execute()` is called.
///
/// ```swift
/// try await store.delete(ProjectRecord.self)
///     .where { $0.deletedAt != nil }
///     .execute()
/// ```
public struct KomaDelete<Record: KomaEntityRecord>: Sendable {
    private let store: any KomaStore
    private var request: KomaDeleteRequest<Record>

    public init(store: any KomaStore, record: Record.Type) {
        self.store = store
        request = KomaDeleteRequest(record: record)
    }

    public func `where`(_ build: @Sendable (KomaPredicateBuilder<Record>) -> KomaPredicate) -> Self {
        var copy = self
        let predicate = build(KomaPredicateBuilder())
        if let existing = copy.request.predicate {
            copy.request.predicate = existing && predicate
        } else {
            copy.request.predicate = predicate
        }
        return copy
    }

    @discardableResult
    public func execute() async throws -> Int {
        try await store.delete(request)
    }
}
