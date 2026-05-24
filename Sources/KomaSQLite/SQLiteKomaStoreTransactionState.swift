import Foundation

enum SQLiteKomaTransactionContext {
    @TaskLocal static var id: UUID?
}

extension SQLiteKomaStore {
    func waitForTransactionAccess() async {
        while let activeTransactionID,
              SQLiteKomaTransactionContext.id != activeTransactionID
        {
            await withCheckedContinuation { continuation in
                transactionWaiters.append(continuation)
            }
        }
    }

    func beginTransactionScope() throws -> UUID {
        let transactionID = UUID()
        activeTransactionID = transactionID
        try execute("BEGIN IMMEDIATE TRANSACTION")
        return transactionID
    }

    func endTransactionScope() {
        activeTransactionID = nil
        let waiters = transactionWaiters
        transactionWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters {
            waiter.resume()
        }
    }

    var isInsideCurrentTransaction: Bool {
        guard let activeTransactionID else {
            return false
        }
        return SQLiteKomaTransactionContext.id == activeTransactionID
    }
}
