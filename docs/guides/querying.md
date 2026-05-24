# Querying

Koma queries are lazy and composable. Execution is explicit through `fetch()`, `first()`, `count()`, or `exists()`.

```swift
let projects = try await store.query(ProjectRecord.self)
    .where { $0.deletedAt == nil }
    .order(by: \.name)
    .limit(20)
    .offset(40)
    .fetch()
```

Predicates support equality, null checks, comparisons, text search, sets, and ranges.

```swift
let records = try await store.query(ProjectRecord.self)
    .where {
        ($0.name.contains("akira") || $0.slug.hasPrefix("ani"))
            && $0.rank.between(1, 10)
            && $0.status.in(["active", "draft"])
    }
    .fetch()
```

## Joins

Joins filter a base query with another table while still returning the base record or model.

```swift
let projects = try await store.query(ProjectRecord.self)
    .join(CharacterRecord.self) { $0.id == $1.projectId }
    .where { $0.deletedAt == nil }
    .where(CharacterRecord.self) { $0.name.hasPrefix("A") }
    .order(by: \.name)
    .fetch()
```

Use joins when the question is "which projects match related rows?" Use relationships when the question is "load the related rows for these projects."

Joined base rows are selected distinctly, so a project with two matching characters appears once. `count()` also counts distinct base primary keys.

Left joins are supported:

```swift
let projects = try await store.query(ProjectRecord.self)
    .leftJoin(CharacterRecord.self) { $0.id == $1.projectId }
    .where { $0.deletedAt == nil }
    .fetch()
```

To find rows without a match, use explicit null predicates on the joined table:

```swift
let projectsWithoutCharacters = try await store.query(ProjectRecord.self)
    .leftJoin(CharacterRecord.self) { $0.id == $1.projectId }
    .where(CharacterRecord.self) { $0.id.isNull() }
    .fetch()
```

Right joins are available too:

```swift
let projects = try await store.query(ProjectRecord.self)
    .rightJoin(CharacterRecord.self) { $0.id == $1.projectId }
    .where(CharacterRecord.self) { $0.name == "Bato" }
    .fetch()
```

Koma always hydrates the base query type. If unmatched rows from the right side are possible, prefer querying that record type and using `leftJoin` back to the related table.

Write builders use the same predicate style.

```swift
try await store.update(ProjectRecord.self)
    .set(\.name, to: "New name")
    .where { $0.id == projectId }
    .execute()

try await store.delete(ProjectRecord.self)
    .where { $0.deletedAt != nil }
    .execute()
```
