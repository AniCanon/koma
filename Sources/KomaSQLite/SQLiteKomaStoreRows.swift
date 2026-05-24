import CKomaSQLite
import Foundation
import Koma

extension SQLiteKomaStore {
    static func fastRow(statement: OpaquePointer, columnCount: Int) -> KomaSQLiteRow {
        var values: [KomaSQLiteStorageValue] = []
        values.reserveCapacity(columnCount)

        for offset in 0 ..< columnCount {
            let index = Int32(offset)
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                values.append(.integer(sqlite3_column_int64(statement, index)))
            case SQLITE_FLOAT:
                values.append(.real(sqlite3_column_double(statement, index)))
            case SQLITE_TEXT:
                values.append(.text(sqlite3_column_text(statement, index).map { String(cString: $0) } ?? ""))
            case SQLITE_BLOB:
                let count = Int(sqlite3_column_bytes(statement, index))
                if let bytes = sqlite3_column_blob(statement, index), count > 0 {
                    values.append(.blob(Data(bytes: bytes, count: count)))
                } else {
                    values.append(.blob(Data()))
                }
            case SQLITE_NULL:
                values.append(.null)
            default:
                values.append(.null)
            }
        }

        return KomaSQLiteRow(values: values)
    }

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
