import CKomaSQLite
import Foundation

/// An LRU cache of prepared statements for one SQLite connection, keyed by SQL text.
///
/// Statements are checked out for exclusive use and checked back in reset, so a cached
/// statement never holds row state, bindings, or an implicit read transaction between uses.
/// Confinement follows the owning connection: callers must serialize access the same way
/// they serialize the connection itself.
final class SQLiteStatementCache {
    private struct Entry {
        let statement: OpaquePointer
        var lastUse: UInt64
    }

    private var entries: [String: Entry] = [:]
    private var clock: UInt64 = 0
    private let capacity: Int

    init(capacity: Int = 100) {
        self.capacity = capacity
    }

    /// Removes and returns the cached statement for `sql`, if any. Removal makes nested or
    /// re-entrant use of the same SQL safe: the second caller simply prepares a fresh statement.
    func checkout(_ sql: String) -> OpaquePointer? {
        entries.removeValue(forKey: sql)?.statement
    }

    /// Resets `statement` and returns it to the cache, evicting the least recently used entry
    /// when full. Reset happens immediately so the statement releases its row state and any
    /// implicit read transaction now, not at the next checkout.
    func checkin(_ sql: String, _ statement: OpaquePointer) {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)

        guard entries[sql] == nil else {
            // A concurrent use of the same SQL already returned its statement; keep one.
            sqlite3_finalize(statement)
            return
        }

        if entries.count >= capacity, let evicted = entries.min(by: { $0.value.lastUse < $1.value.lastUse }) {
            entries.removeValue(forKey: evicted.key)
            sqlite3_finalize(evicted.value.statement)
        }

        clock += 1
        entries[sql] = Entry(statement: statement, lastUse: clock)
    }

    /// Finalizes every cached statement. Must run before `sqlite3_close`, which refuses to
    /// close a connection that still has prepared statements.
    func removeAll() {
        for entry in entries.values {
            sqlite3_finalize(entry.statement)
        }
        entries.removeAll()
    }

    deinit {
        removeAll()
    }
}
