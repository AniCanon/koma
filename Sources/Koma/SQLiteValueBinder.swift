import Foundation

@_documentation(visibility: private)
public protocol KomaSQLiteValueBinder {
    mutating func bindNull() throws
    mutating func bind(_ value: borrowing String) throws
    mutating func bind(_ value: Bool) throws
    mutating func bind(_ value: some FixedWidthInteger & SignedInteger) throws
    mutating func bind(_ value: Float) throws
    mutating func bind(_ value: Double) throws
    mutating func bind(_ value: Date) throws
    mutating func bind(_ value: borrowing Data) throws
}

@_documentation(visibility: private)
public extension KomaSQLiteValueBinder {
    mutating func bind(_ value: String?) throws {
        guard let value else {
            try bindNull()
            return
        }
        try bind(value)
    }

    mutating func bind(_ value: Bool?) throws {
        guard let value else {
            try bindNull()
            return
        }
        try bind(value)
    }

    mutating func bind(_ value: (some FixedWidthInteger & SignedInteger)?) throws {
        guard let value else {
            try bindNull()
            return
        }
        try bind(value)
    }

    mutating func bind(_ value: Float?) throws {
        guard let value else {
            try bindNull()
            return
        }
        try bind(value)
    }

    mutating func bind(_ value: Double?) throws {
        guard let value else {
            try bindNull()
            return
        }
        try bind(value)
    }

    mutating func bind(_ value: Date?) throws {
        guard let value else {
            try bindNull()
            return
        }
        try bind(value)
    }

    mutating func bind(_ value: Data?) throws {
        guard let value else {
            try bindNull()
            return
        }
        try bind(value)
    }

    mutating func bind(_ value: borrowing KomaSQLiteStorageValue) throws {
        switch value {
        case .null:
            try bindNull()
        case let .text(value):
            try bind(value)
        case let .integer(value):
            try bind(value)
        case let .real(value):
            try bind(value)
        case let .blob(value):
            try bind(value)
        }
    }
}
