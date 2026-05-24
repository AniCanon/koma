import Foundation

/// A lazy update operation that executes only when `execute()` is called.
///
/// ```swift
/// try await store.update(ProjectRecord.self)
///     .set(\.name, to: "New title")
///     .where { $0.id == projectID }
///     .execute()
/// ```
public struct KomaUpdate<Record: KomaEntityRecord>: Sendable {
    private let store: any KomaStore
    private var request: KomaUpdateRequest<Record>

    public init(store: any KomaStore, record: Record.Type) {
        self.store = store
        request = KomaUpdateRequest(record: record)
    }

    public func set<Value: KomaBindableValue>(
        _ keyPath: KeyPath<Record.Columns, KomaColumn<Value>>,
        to value: Value
    ) -> Self {
        var copy = self
        let column = Record.columns[keyPath: keyPath].name
        copy.request.assignments.append(KomaUpdateAssignment(column: column, value: value.komaValue))
        return copy
    }

    public func set<Value: KomaBindableValue>(
        _ keyPath: KeyPath<Record.Columns, KomaColumn<Value?>>,
        to value: Value?
    ) -> Self {
        var copy = self
        let column = Record.columns[keyPath: keyPath].name
        copy.request.assignments.append(KomaUpdateAssignment(column: column, value: value?.komaValue))
        return copy
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
        try await store.update(request)
    }
}
