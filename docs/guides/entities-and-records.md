# Entities and Records

Records are the normalized storage truth. They map directly to SQLite tables.

```swift
@KomaEntity(table: "projects", as: Project.self)
struct ProjectRecord: KomaRemoteRecord {
    @KomaPrimaryKey var id: String
    var name: String
    var slug: String
    var deletedAt: Date?
}
```

Stored properties become columns by default. Read-only computed properties are ignored. Use `@KomaIgnore` to exclude a stored property.

When a transport model has the same stored property names, `as:` generates `Remote`, `init(remote:)`, and `remoteValue`. For custom backend shapes, write those members manually or use an adapter.

Records can stay lower level than the app UI. Hydrated models provide convenience while records remain the source of persistence.
