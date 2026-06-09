# Raw SQL and Local Search

Koma's SQLite store is meant to be a small typed ORM that stays close to raw SQLite performance on app workloads. It is not a claim that the ORM replaces hand-written SQL everywhere.

When an app needs a query shape beyond the typed builder, use the raw SQL escape hatch. When an app needs local memory search, use the FTS5 and vector APIs so Koma can keep indexes on the same SQLite actor and still hydrate typed records.

## Raw SQL

Use `rawQuery` for custom reads. Arguments use the same SQLite storage values as the rest of the store.

```swift
let rows = try await store.rawQuery(
    """
    SELECT id, content
    FROM memories
    WHERE content LIKE ?
    ORDER BY updatedAt DESC
    LIMIT ?
    """,
    arguments: ["%swift%", 20]
)

let id = try rows[0].string("id")
```

Use `rawExecute` for custom writes. Pass changed tables through `invalidating:` when live observations should refetch.

```swift
try await store.rawExecute(
    "UPDATE memories SET content = ? WHERE id = ?",
    arguments: ["semantic search note", "1"],
    invalidating: [MemoryRecord.komaTableName]
)
```

Raw SQL calls still run through the SQLite store's transaction gate. A raw write from another task waits for an active transaction instead of interleaving with it.

## Full-Text Search

Create an FTS5 index for a text column:

```swift
try await store.createFullTextIndex(for: MemoryRecord.self, indexing: \.content)
```

The index is external-content FTS5. Koma creates insert, update, and delete triggers and rebuilds the index from existing rows, so migrations can add search after data already exists.

Search returns typed records ranked by FTS5 relevance:

```swift
let keyword = try await store.fullTextSearch(
    MemoryRecord.self,
    matching: "embeddings",
    limit: 20
)
```

## Exact Vector Search

Store embeddings as `Data` with `KomaVector.encode`.

```swift
@KomaEntity(table: "memories")
struct MemoryRecord: KomaEntityRecord {
    @KomaPrimaryKey var id: String
    var content: String
    var embedding: Data
}

let record = MemoryRecord(
    id: "1",
    content: "semantic search note",
    embedding: KomaVector.encode([0.1, 0.2, 0.3])
)
```

When the embedding source is single-precision (most are), store at `Float32` for half the storage and scan I/O:

```swift
embedding: KomaVector.encode(queryEmbedding, as: .float32)
```

Exact search scans the stored vectors, scores cosine similarity, and hydrates only the winners. The scan detects `Float64` vs `Float32` per row from the blob length, so no search call site changes with the storage precision:

```swift
let nearest = try await store.nearest(
    MemoryRecord.self,
    to: queryEmbedding,
    on: \.embedding,
    limit: 20
)
```

Exact nearest is predictable and exact, but it is an O(n) scan.

## Quantized Vector Search

For larger local corpora, create a trigger-maintained int8 sidecar index:

```swift
try await store.createQuantizedVectorIndex(for: MemoryRecord.self, on: \.embedding)
```

If the column stores `Float32` vectors, say so when creating the index — the quantizing SQL function cannot infer the element width from the blob alone:

```swift
try await store.createQuantizedVectorIndex(for: MemoryRecord.self, on: \.embedding, precision: .float32)
```

Use quantized search for faster recall followed by exact reranking:

```swift
let nearest = try await store.nearestQuantized(
    MemoryRecord.self,
    to: queryEmbedding,
    on: \.embedding,
    limit: 20,
    overfetch: 10
)
```

The sidecar table is named from the table and column, for example `memories_embedding_i8`. Koma backfills existing rows and maintains the sidecar with insert, update, and delete triggers.

Quantized search is not a replacement for exact scoring. It scans compact int8 codes to pick candidates quickly, then reranks the candidates with full-precision cosine before returning records.

## Hybrid Search

Hybrid search fuses FTS5 keyword recall and vector recall with reciprocal-rank fusion.

```swift
let results = try await store.hybridSearch(
    MemoryRecord.self,
    matching: "embeddings",
    near: queryEmbedding,
    on: \.embedding,
    identifiedBy: \.id,
    limit: 20
)
```

After creating the quantized vector index, hybrid search can use quantized vector recall:

```swift
let results = try await store.hybridSearch(
    MemoryRecord.self,
    matching: "embeddings",
    near: queryEmbedding,
    on: \.embedding,
    identifiedBy: \.id,
    limit: 20,
    vectorSearch: .quantized(overfetch: 10)
)
```

Use exact search when correctness and stable scoring matter most. Use quantized search when local latency matters and over-fetch plus exact reranking gives acceptable recall for the app's corpus.
