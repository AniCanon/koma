import CKomaSQLite
import Foundation
import Koma

extension SQLiteKomaStore {
    static func rowObject(statement: OpaquePointer, columns: [String]) -> [String: Any] {
        var object: [String: Any] = [:]
        object.reserveCapacity(columns.count)

        for (offset, column) in columns.enumerated() {
            let index = Int32(offset)
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                object[column] = Int(sqlite3_column_int64(statement, index))
            case SQLITE_FLOAT:
                object[column] = sqlite3_column_double(statement, index)
            case SQLITE_TEXT:
                object[column] = sqlite3_column_text(statement, index).map { String(cString: $0) } ?? NSNull()
            case SQLITE_NULL:
                object[column] = NSNull()
            default:
                object[column] = NSNull()
            }
        }

        return object
    }
}
