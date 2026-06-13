import CKomaSQLite
import Foundation
#if canImport(os)
import os
#endif

/// Tables already ensured this session, shared between the writer actor and nonisolated read
/// routing. Lock-protected so a pooled read can prove its tables exist without hopping to the
/// writer — the hop would queue the read behind in-flight writes, which is exactly what the
/// pool exists to avoid.
///
/// Uses `OSAllocatedUnfairLock` on Darwin (`Mutex` needs the iOS 18/macOS 15 floor) and falls
/// back to `NSLock` on platforms without the `os` module, such as Android.
final class SQLiteEnsuredTables: @unchecked Sendable {
    #if canImport(os)
    private let state = OSAllocatedUnfairLock(initialState: Set<String>())

    func contains(_ table: String) -> Bool {
        state.withLock { $0.contains(table) }
    }

    func insert(_ table: String) {
        state.withLock { _ = $0.insert(table) }
    }

    func formUnion(_ names: [String]) {
        state.withLock { $0.formUnion(names) }
    }

    func removeAll() {
        state.withLock { $0.removeAll(keepingCapacity: true) }
    }
    #else
    private let lock = NSLock()
    private var tables: Set<String> = []

    func contains(_ table: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return tables.contains(table)
    }

    func insert(_ table: String) {
        lock.lock()
        tables.insert(table)
        lock.unlock()
    }

    func formUnion(_ names: [String]) {
        lock.lock()
        tables.formUnion(names)
        lock.unlock()
    }

    func removeAll() {
        lock.lock()
        tables.removeAll(keepingCapacity: true)
        lock.unlock()
    }
    #endif
}

/// A read-only WAL connection owned by `SQLiteReadPool`. Exclusive checkout confines all use
/// to one task at a time, so the connection and its statement cache need no internal locking.
final class SQLiteReadConnection: @unchecked Sendable {
    let database: OpaquePointer
    let statementCache = SQLiteStatementCache()

    init(path: String) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        var connection: OpaquePointer?
        guard sqlite3_open_v2(path, &connection, flags, nil) == SQLITE_OK, let connection else {
            let message = connection.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) }
                ?? "Unable to open SQLite read connection."
            if let connection {
                sqlite3_close(connection)
            }
            throw SQLiteKomaError.openFailed(message)
        }
        database = connection

        do {
            var error: UnsafeMutablePointer<CChar>?
            guard sqlite3_exec(connection, "PRAGMA busy_timeout = 5000", nil, nil, &error) == SQLITE_OK else {
                let message = error.map { String(cString: $0) } ?? "Unable to configure SQLite read connection."
                sqlite3_free(error)
                throw SQLiteKomaError.openFailed(message)
            }
            // Raw read SQL may reference koma_vector_i8, so readers register it too.
            try SQLiteKomaStore.installVectorFunctions(on: connection)
        } catch {
            sqlite3_close(connection)
            throw error
        }
    }

    var access: SQLiteDatabaseAccess {
        SQLiteDatabaseAccess(database: database, statementCache: statementCache)
    }

    deinit {
        statementCache.removeAll()
        sqlite3_close_v2(database)
    }
}

/// A small pool of read-only connections that lets WAL serve reads concurrently with the
/// writer actor and with each other. Connections open lazily up to `capacity`; exhausted
/// acquires queue. Only checkout bookkeeping runs on this actor — the blocking SQLite work
/// happens on the caller's executor, so concurrent reads genuinely overlap.
actor SQLiteReadPool {
    private let path: String
    private let capacity: Int
    private var available: [SQLiteReadConnection] = []
    private var openCount = 0
    private var waiters: [CheckedContinuation<SQLiteReadConnection, Never>] = []

    init(path: String, capacity: Int) {
        self.path = path
        self.capacity = max(1, capacity)
    }

    /// Runs `body` on a checked-out read connection, off the writer's executor.
    nonisolated func withConnection<Result: Sendable>(
        _ body: @Sendable (SQLiteDatabaseAccess) throws -> Result
    ) async throws -> Result {
        let connection = try await acquire()
        do {
            let result = try body(connection.access)
            await release(connection)
            return result
        } catch {
            await release(connection)
            throw error
        }
    }

    private func acquire() async throws -> SQLiteReadConnection {
        if let connection = available.popLast() {
            return connection
        }
        if openCount < capacity {
            let connection = try SQLiteReadConnection(path: path)
            openCount += 1
            return connection
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release(_ connection: SQLiteReadConnection) {
        if waiters.isEmpty {
            available.append(connection)
        } else {
            waiters.removeFirst().resume(returning: connection)
        }
    }
}
