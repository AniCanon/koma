import Foundation

public enum SQLiteKomaError: Error, Equatable, LocalizedError {
    case openFailed(String)
    case executionFailed(String)
    case closed
    case invalidPredicate
    case incompatibleSchema(String)
    case migrationFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .openFailed(message),
             let .executionFailed(message),
             let .incompatibleSchema(message),
             let .migrationFailed(message):
            return message
        case .closed:
            return "SQLite database is closed."
        case .invalidPredicate:
            return "Invalid predicate."
        }
    }
}
