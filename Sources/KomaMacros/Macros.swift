import Koma

/// Generates table metadata and optimized SQLite/JSON support for a record.
///
/// Stored properties become columns by default. Use `@KomaPrimaryKey` to mark
/// the primary key and `@KomaIgnore` to exclude a property. When `as:` is
/// supplied, Koma also generates the default one-to-one remote mapping.
///
/// ```swift
/// @KomaEntity(table: "projects", as: Project.self)
/// struct ProjectRecord: KomaRemoteRecord {
///     @KomaPrimaryKey var id: String
///     var name: String
/// }
/// ```
@attached(
    member,
    names: named(Columns),
    named(columns),
    named(komaTableName),
    named(komaPrimaryKey),
    named(komaColumns),
    named(komaGeneratedCreateTableSQL),
    named(komaUsesSQLiteFastPath),
    named(komaSQLiteValues),
    named(komaSQLiteValue),
    named(komaSQLiteBind),
    named(komaSQLiteRecord),
    named(komaUsesJSONFastPath),
    named(komaJSONRecords),
    named(komaJSONRecord),
    named(komaJSONBindRecords),
    named(komaJSONData),
    named(komaJSONWrite),
    named(Remote),
    named(remoteValue),
    named(init)
)
@attached(
    extension,
    conformances: KomaGeneratedSchemaRecord,
    KomaSQLiteFastPathRecord,
    KomaJSONFastPathRecord,
    KomaFusedJSONRecord
)
public macro KomaEntity(table: String? = nil, as: Any.Type? = nil) = #externalMacro(
    module: "KomaMacroPlugin",
    type: "KomaEntityMacro"
)

/// Marks a record property as the table primary key.
@attached(peer)
public macro KomaPrimaryKey() = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

/// Excludes a record property from macro-expanded table columns.
@attached(peer)
public macro KomaIgnore() = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

/// Generates a typed client for an enum resource namespace.
///
/// ```swift
/// @KomaResource(basePath: "projects", record: ProjectRecord.self)
/// enum ProjectResources {
///     @KomaRoute(.get(as: [Project].self), cache: .collection("projects"))
///     case list(ProjectListParams = .init())
/// }
/// ```
@attached(member, names: named(Client), named(client))
@attached(extension, conformances: KomaResourceNamespace)
public macro KomaResource(basePath: String, record: Any.Type) = #externalMacro(module: "KomaMacroPlugin", type: "KomaResourceMacro")

/// Describes an HTTP route and its cache, refresh, and adapter behavior.
@attached(peer)
public macro KomaRoute(
    _ route: KomaRouteDescriptor,
    cache: KomaCacheDescriptor? = nil,
    refresh: KomaRouteRefresh = .disabled,
    adapter: Any.Type? = nil
) = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

@available(*, deprecated, message: "Use @KomaRoute(.get(_:as:), cache:refresh:adapter:) instead.")
@attached(peer)
public macro KomaGET(_ path: String = "", output: Any.Type) = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

@available(*, deprecated, message: "Use @KomaRoute(.post(_:as:), cache:refresh:adapter:) instead.")
@attached(peer)
public macro KomaPOST(_ path: String = "", output: Any.Type) = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

@available(*, deprecated, message: "Use @KomaRoute(.patch(_:as:), cache:refresh:adapter:) instead.")
@attached(peer)
public macro KomaPATCH(_ path: String = "", output: Any.Type) = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

@available(*, deprecated, message: "Use @KomaRoute(.delete(_:as:), cache:refresh:adapter:) instead.")
@attached(peer)
public macro KomaDELETE(_ path: String = "", output: Any.Type) = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

@available(*, deprecated, message: "Pass cache: to @KomaRoute instead.")
@attached(peer)
public macro KomaCache(_ cache: KomaCacheDescriptor, staleAfter: KomaDuration? = nil) = #externalMacro(
    module: "KomaMacroPlugin",
    type: "KomaNoopMacro"
)

@available(*, deprecated, message: "Pass adapter: to @KomaRoute instead.")
@attached(peer)
public macro KomaAdapter(_ adapter: Any.Type) = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

@available(*, deprecated, message: "Pass refresh: .allowed to @KomaRoute instead.")
@attached(peer)
public macro KomaRefreshable() = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

/// Generates hydrated model storage and relationship access.
///
/// ```swift
/// @KomaModel(record: ProjectRecord.self)
/// struct ProjectModel {
///     var id: String
///     var name: String
/// }
/// ```
@attached(member, names: arbitrary)
@attached(extension, conformances: KomaModel)
public macro KomaModel(record: Any.Type, relations: Any.Type? = nil) = #externalMacro(module: "KomaMacroPlugin", type: "KomaModelMacro")

/// Generates reusable relationship descriptors for a record type.
@attached(member, names: arbitrary)
@attached(extension, conformances: KomaRelationNamespace)
public macro KomaRelations(_ record: Any.Type, model: Any.Type? = nil) = #externalMacro(
    module: "KomaMacroPlugin",
    type: "KomaRelationsMacro"
)

/// Declares a to-many relationship.
@attached(peer)
public macro KomaHasMany(
    _ record: Any.Type,
    local: Any,
    foreign: Any,
    model: Any.Type
) = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

/// Declares a to-one relationship.
@attached(peer)
public macro KomaHasOne(
    _ record: Any.Type,
    local: Any,
    foreign: Any,
    model: Any.Type
) = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")

/// Declares an inverse to-one relationship.
@attached(peer)
public macro KomaBelongsTo(
    _ record: Any.Type,
    local: Any,
    foreign: Any,
    model: Any.Type
) = #externalMacro(module: "KomaMacroPlugin", type: "KomaNoopMacro")
