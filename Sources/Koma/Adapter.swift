import Foundation

/// A type-erased adapter used by macro-expanded resource clients.
public protocol KomaAnyPersistenceAdapter: Sendable {
    static func persistAny(
        _ output: Any,
        context: KomaPersistenceContext,
        store: any KomaStore
    ) async throws
}

/// Persists complex REST outputs into typed records and typed metadata.
public protocol KomaPersistenceAdapter: KomaAnyPersistenceAdapter {
    associatedtype Output: Decodable & Sendable

    static func persist(
        _ output: Output,
        context: KomaPersistenceContext,
        store: any KomaStore
    ) async throws
}

public extension KomaPersistenceAdapter {
    static func persistAny(
        _ output: Any,
        context: KomaPersistenceContext,
        store: any KomaStore
    ) async throws {
        guard let output = output as? Output else {
            throw KomaMappingError.unsupportedOutput(String(describing: type(of: output)))
        }
        try await persist(output, context: context, store: store)
    }
}
