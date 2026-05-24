import Foundation

/// Compile-time route metadata used by `@KomaRoute`.
///
/// ```swift
/// @KomaResource(basePath: "projects", record: ProjectRecord.self)
/// enum ProjectResources {
///     @KomaRoute(.get("{projectId}", as: Project.self), cache: .entity("projects"))
///     case detail(projectId: String)
/// }
/// ```
public struct KomaRouteDescriptor {
    /// The HTTP method used by the route.
    public let method: KomaHTTPMethod

    /// The path relative to the resource's base path.
    public let path: String

    /// The decoded response type produced by the route.
    public let response: Any.Type

    /// Creates route metadata for a resource operation.
    public init(method: KomaHTTPMethod, path: String = "", as response: Any.Type) {
        self.method = method
        self.path = path
        self.response = response
    }

    /// Describes a `GET` route decoded as `response`.
    public static func get(_ path: String = "", as response: Any.Type) -> Self {
        Self(method: .get, path: path, as: response)
    }

    /// Describes a `POST` route decoded as `response`.
    public static func post(_ path: String = "", as response: Any.Type) -> Self {
        Self(method: .post, path: path, as: response)
    }

    /// Describes a `PATCH` route decoded as `response`.
    public static func patch(_ path: String = "", as response: Any.Type) -> Self {
        Self(method: .patch, path: path, as: response)
    }

    /// Describes a `PUT` route decoded as `response`.
    public static func put(_ path: String = "", as response: Any.Type) -> Self {
        Self(method: .put, path: path, as: response)
    }

    /// Describes a `DELETE` route decoded as `response`.
    public static func delete(_ path: String = "", as response: Any.Type) -> Self {
        Self(method: .delete, path: path, as: response)
    }
}

public extension KomaRouteDescriptor {
    /// Compatibility spelling for `.get(_:as:)`.
    @available(*, deprecated, message: "Use .get(_:as:) instead.")
    static func get(_ path: String = "", output: Any.Type) -> Self {
        get(path, as: output)
    }

    /// Compatibility spelling for `.post(_:as:)`.
    @available(*, deprecated, message: "Use .post(_:as:) instead.")
    static func post(_ path: String = "", output: Any.Type) -> Self {
        post(path, as: output)
    }

    /// Compatibility spelling for `.patch(_:as:)`.
    @available(*, deprecated, message: "Use .patch(_:as:) instead.")
    static func patch(_ path: String = "", output: Any.Type) -> Self {
        patch(path, as: output)
    }

    /// Compatibility spelling for `.put(_:as:)`.
    @available(*, deprecated, message: "Use .put(_:as:) instead.")
    static func put(_ path: String = "", output: Any.Type) -> Self {
        put(path, as: output)
    }

    /// Compatibility spelling for `.delete(_:as:)`.
    @available(*, deprecated, message: "Use .delete(_:as:) instead.")
    static func delete(_ path: String = "", output: Any.Type) -> Self {
        delete(path, as: output)
    }
}

/// Controls whether a route can be registered with `.keepFresh(...)`.
public enum KomaRouteRefresh: Equatable, Sendable {
    /// The route cannot be scheduled with `.keepFresh(...)`.
    case disabled

    /// The route can be scheduled with `.keepFresh(...)`.
    case allowed
}
