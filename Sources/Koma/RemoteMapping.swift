import Foundation

enum KomaDefaultRemoteMapper {
    static func persist<Output, Record: KomaRemoteRecord>(
        _ output: Output,
        record: Record.Type,
        context: KomaPersistenceContext = KomaPersistenceContext(operationName: ""),
        store: any KomaStore
    ) async throws where Record.Remote: Decodable {
        if let remote = output as? Record.Remote {
            try await store.upsert([Record.record(remote: remote, context: context)])
            return
        }

        if let remotes = output as? [Record.Remote] {
            try await store.upsert(remotes.map { Record.record(remote: $0, context: context) })
            return
        }

        throw KomaMappingError.unsupportedOutput(String(describing: Output.self))
    }

    static func output<Output, Record: KomaRemoteRecord>(
        _ records: [Record],
        as output: Output.Type
    ) throws -> Output where Record.Remote: Decodable {
        if Output.self == [Record.Remote].self {
            guard let output = records.map(\.remoteValue) as? Output else {
                throw KomaMappingError.unsupportedOutput(String(describing: Output.self))
            }
            return output
        }

        if Output.self == Record.Remote.self {
            guard let first = records.first else {
                throw KomaMappingError.emptyResult
            }
            guard let output = first.remoteValue as? Output else {
                throw KomaMappingError.unsupportedOutput(String(describing: Output.self))
            }
            return output
        }

        throw KomaMappingError.unsupportedOutput(String(describing: Output.self))
    }
}

public enum KomaMappingError: Error, Equatable {
    case unsupportedOutput(String)
    case emptyResult
}

enum KomaOutputInspector {
    static func isEmpty(_ output: some Sendable) -> Bool {
        if let array = output as? any Collection {
            return array.isEmpty
        }
        return false
    }
}
