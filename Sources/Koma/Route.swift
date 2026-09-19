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

    /// Whether the response is returned to the caller instead of being stored.
    ///
    /// `false` for an `as:` route, which decodes into the namespace's record type and is
    /// generated as a `KomaFetch`. `true` for a `returning:` route, which is generated as a
    /// `KomaReturningCommand` and persists nothing.
    public let isReturning: Bool

    /// Creates route metadata for a resource operation whose response is stored.
    public init(method: KomaHTTPMethod, path: String = "", as response: Any.Type) {
        self.method = method
        self.path = path
        self.response = response
        isReturning = false
    }

    /// Creates route metadata for a resource operation whose response is returned, not stored.
    public init(method: KomaHTTPMethod, path: String = "", returning response: Any.Type) {
        self.method = method
        self.path = path
        self.response = response
        isReturning = true
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

/// Routes whose response is returned to the caller rather than stored.
///
/// `as:` and `returning:` are the two halves of Koma's CQRS split. An `as:` route decodes
/// into the namespace's record type, persists it, and is generated as a `KomaFetch`. A
/// `returning:` route is generated as a `KomaReturningCommand`, which decodes the response
/// and hands it back without touching the store — for the writes whose response is not
/// stored data, such as a job handle, an analysis payload, or a presigned upload.
///
/// ```swift
/// @KomaResource(basePath: "projects")
/// enum ImageResources {
///     @KomaRoute(.post("{projectId}/images", returning: Job.self))
///     case generate(projectId: String, body: GenerateRequest)
/// }
/// ```
public extension KomaRouteDescriptor {
    /// Describes a `GET` route whose response is returned instead of stored.
    ///
    /// The discriminator is the response, not the verb: a `GET` that answers with something
    /// the store does not own — server capabilities, a presigned URL — would otherwise need
    /// a record type invented for it.
    static func get(_ path: String = "", returning response: Any.Type) -> Self {
        Self(method: .get, path: path, returning: response)
    }

    /// Describes a `POST` route whose response is returned instead of stored.
    static func post(_ path: String = "", returning response: Any.Type) -> Self {
        Self(method: .post, path: path, returning: response)
    }

    /// Describes a `PATCH` route whose response is returned instead of stored.
    static func patch(_ path: String = "", returning response: Any.Type) -> Self {
        Self(method: .patch, path: path, returning: response)
    }

    /// Describes a `PUT` route whose response is returned instead of stored.
    static func put(_ path: String = "", returning response: Any.Type) -> Self {
        Self(method: .put, path: path, returning: response)
    }

    /// Describes a `DELETE` route whose response is returned instead of stored.
    static func delete(_ path: String = "", returning response: Any.Type) -> Self {
        Self(method: .delete, path: path, returning: response)
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
