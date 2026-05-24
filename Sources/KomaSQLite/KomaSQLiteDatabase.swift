import Foundation

/// Errors thrown while resolving a SQLite database location.
public enum KomaSQLiteDatabaseError: Error, Equatable, LocalizedError, Sendable {
    /// The explicit database path was empty.
    case emptyPath

    /// The application-support database file name was empty.
    case emptyFileName

    /// The database URL was not a file URL.
    case nonFileURL(URL)

    /// The platform application-support directory could not be resolved.
    case applicationSupportDirectoryUnavailable

    public var errorDescription: String? {
        switch self {
        case .emptyPath:
            "SQLite database path cannot be empty."

        case .emptyFileName:
            "SQLite database file name cannot be empty."

        case let .nonFileURL(url):
            "SQLite database URL must be a file URL: \(url.absoluteString)."

        case .applicationSupportDirectoryUnavailable:
            "Unable to resolve the platform application support directory."
        }
    }
}

/// Describes where Koma should open its SQLite database.
public enum KomaSQLiteDatabase: Equatable, Sendable {
    /// Opens SQLite at an explicit filesystem path.
    case path(String)

    /// Opens SQLite at an explicit file URL.
    case url(URL)

    #if !os(Android)
    /// Opens SQLite in the platform application support directory.
    case applicationSupport(String, appDirectory: String? = nil)
    #endif

    func resolvedPath() throws -> String {
        switch self {
        case let .path(path):
            try Self.validatePath(path)
            try Self.createParentDirectory(for: URL(fileURLWithPath: path))
            return path

        case let .url(url):
            guard url.isFileURL else {
                throw KomaSQLiteDatabaseError.nonFileURL(url)
            }
            try Self.validatePath(url.path)
            try Self.createParentDirectory(for: url)
            return url.path

        #if !os(Android)
        case let .applicationSupport(fileName, appDirectory):
            try Self.validateFileName(fileName)

            guard let baseURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first else {
                throw KomaSQLiteDatabaseError.applicationSupportDirectoryUnavailable
            }

            let directory = Self.applicationSupportDirectory(
                baseURL: baseURL,
                appDirectory: appDirectory
            )

            let databaseURL = directory.appendingPathComponent(fileName)
            try Self.createParentDirectory(for: databaseURL)
            return databaseURL.path
        #endif
        }
    }

    private static func validatePath(_ path: String) throws {
        guard !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KomaSQLiteDatabaseError.emptyPath
        }
    }

    private static func validateFileName(_ fileName: String) throws {
        guard !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw KomaSQLiteDatabaseError.emptyFileName
        }
    }

    #if !os(Android)
    private static func applicationSupportDirectory(
        baseURL: URL,
        appDirectory: String?
    ) -> URL {
        guard let appDirectory else {
            return baseURL
        }

        let trimmed = appDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return baseURL
        }

        return baseURL.appendingPathComponent(trimmed, isDirectory: true)
    }
    #endif

    private static func createParentDirectory(for url: URL) throws {
        let directory = url.deletingLastPathComponent()
        guard !directory.path.isEmpty else { return }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }
}
