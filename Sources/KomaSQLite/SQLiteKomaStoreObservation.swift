import Foundation
import Koma

struct SQLiteKomaStoreObservation: Sendable {
    let tables: Set<String>
    let notify: @Sendable () -> Void
}

extension SQLiteKomaStore: KomaObservableStore {
    public nonisolated func observe<Record: KomaEntityRecord>(
        _ request: KomaQueryRequest<Record>,
        observing additionalTables: Set<String>
    ) -> AsyncThrowingStream<[Record], Error> {
        AsyncThrowingStream { continuation in
            let id = UUID()
            let tables = Self.observationTables(for: request, observing: additionalTables)
            let signals = AsyncStream.makeStream(
                of: Void.self,
                bufferingPolicy: .bufferingNewest(1)
            )
            let task = Task {
                do {
                    await addObservation(id: id, tables: tables) {
                        signals.continuation.yield(())
                    }
                    signals.continuation.yield(())

                    for await _ in signals.stream {
                        try Task.checkCancellation()
                        continuation.yield(try await fetch(request))
                    }
                    continuation.finish()
                } catch {
                    await removeObservation(id: id)
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                signals.continuation.finish()
                task.cancel()
                Task { await self.removeObservation(id: id) }
            }
        }
    }
}

extension SQLiteKomaStore {
    func addObservation(
        id: UUID,
        tables: Set<String>,
        notify: @escaping @Sendable () -> Void
    ) {
        observations[id] = SQLiteKomaStoreObservation(tables: tables, notify: notify)
        for table in tables {
            observationIDsByTable[table, default: []].insert(id)
        }
    }

    func removeObservation(id: UUID) {
        guard let observation = observations.removeValue(forKey: id) else {
            return
        }
        for table in observation.tables {
            observationIDsByTable[table]?.remove(id)
            if observationIDsByTable[table]?.isEmpty == true {
                observationIDsByTable[table] = nil
            }
        }
    }

    func recordChangedTable(_ table: String) {
        guard !observations.isEmpty else {
            return
        }

        if isInsideCurrentTransaction {
            pendingChangedTables.insert(table)
        } else {
            notifyObservers(changedTable: table)
        }
    }

    func recordChangedTables(_ tables: Set<String>) {
        guard !tables.isEmpty, !observations.isEmpty else {
            return
        }

        if isInsideCurrentTransaction {
            pendingChangedTables.formUnion(tables)
        } else {
            notifyObservers(changedTables: tables)
        }
    }

    func notifyObservers(changedTable table: String) {
        guard let ids = observationIDsByTable[table] else {
            return
        }

        for id in ids {
            observations[id]?.notify()
        }
    }

    func notifyObservers(changedTables: Set<String>) {
        guard !changedTables.isEmpty, !observations.isEmpty else {
            return
        }

        if changedTables.count == 1, let table = changedTables.first {
            notifyObservers(changedTable: table)
            return
        }

        var notifiedIDs: Set<UUID> = []
        for table in changedTables {
            guard let ids = observationIDsByTable[table] else {
                continue
            }
            for id in ids where notifiedIDs.insert(id).inserted {
                observations[id]?.notify()
            }
        }
    }

    static func observationTables<Record: KomaEntityRecord>(
        for request: borrowing KomaQueryRequest<Record>,
        observing additionalTables: consuming Set<String>
    ) -> Set<String> {
        var tables = additionalTables
        tables.insert(Record.komaTableName)
        for join in request.joins {
            tables.insert(join.tableName)
        }
        return tables
    }
}
