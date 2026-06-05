import Foundation

@_documentation(visibility: private)
public enum KomaSQLiteStorageValue: Equatable, Sendable {
    case null
    case text(String)
    case integer(Int64)
    case real(Double)
    case blob(Data)
}

/// Literal conformances so raw-SQL arguments can be written as `[1, "term", 3.5, true]`.
extension KomaSQLiteStorageValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int64) {
        self = .integer(value)
    }
}

extension KomaSQLiteStorageValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .real(value)
    }
}

extension KomaSQLiteStorageValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .text(value)
    }
}

extension KomaSQLiteStorageValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .integer(value ? 1 : 0)
    }
}

extension KomaSQLiteStorageValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

@_documentation(visibility: private)
public extension KomaSQLiteStorageValue {
    init(_ value: String) {
        self = .text(value)
    }

    init(_ value: String?) {
        self = value.map(Self.text) ?? .null
    }

    init(_ value: Bool) {
        self = .integer(value ? 1 : 0)
    }

    init(_ value: Bool?) {
        self = value.map { .integer($0 ? 1 : 0) } ?? .null
    }

    init(_ value: some FixedWidthInteger & SignedInteger) {
        self = .integer(Int64(value))
    }

    init(_ value: (some FixedWidthInteger & SignedInteger)?) {
        self = value.map { .integer(Int64($0)) } ?? .null
    }

    init(_ value: Float) {
        self = .real(Double(value))
    }

    init(_ value: Float?) {
        self = value.map { .real(Double($0)) } ?? .null
    }

    init(_ value: Double) {
        self = .real(value)
    }

    init(_ value: Double?) {
        self = value.map(Self.real) ?? .null
    }

    init(_ value: Date) {
        self = .real(value.timeIntervalSinceReferenceDate)
    }

    init(_ value: Date?) {
        self = value.map { .real($0.timeIntervalSinceReferenceDate) } ?? .null
    }

    init(_ value: Data) {
        self = .blob(value)
    }

    init(_ value: Data?) {
        self = value.map(Self.blob) ?? .null
    }
}
