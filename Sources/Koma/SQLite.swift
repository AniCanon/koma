import Foundation

@_documentation(visibility: private)
public enum _KomaSQLiteFastPathError: Error, Equatable, Sendable {
    case unavailable
    case missingColumn(Int)
    case typeMismatch(index: Int, expected: String)
}
