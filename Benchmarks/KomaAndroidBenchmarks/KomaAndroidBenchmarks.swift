import Foundation
import Koma
import KomaAndroidBenchmarkCore
import KomaBenchmarkSQLiteSupport
import KomaBenchmarkSupport
import KomaSQLite
import YYJSON

func makeKomaAndroidBenchmarks() -> [AndroidBenchmark] {
    let fixtures = AndroidBenchmarkFixtures()
    return makeAndroidJSONBenchmarks(fixtures) + makeAndroidSQLiteBenchmarks(fixtures)
}

private struct AndroidBenchmarkFixtures {
    let small = BenchmarkFixtures.projects(1000)
    let large = BenchmarkFixtures.projects(10000)
    let smallRecords: [BenchmarkProjectRecord]
    let largeRecords: [BenchmarkProjectRecord]
    let smallBody: Data
    let largeBody: Data
    let foundationDecoder = JSONDecoder()
    let foundationEncoder = JSONEncoder()
    let yyjsonDecoder = YYJSONDecoder()
    let yyjsonEncoder = YYJSONEncoder()
    let largeCharacters: [BenchmarkCharacter]
    let largeCharacterRecords: [BenchmarkCharacterRecord]

    init() {
        smallRecords = small.map(BenchmarkProjectRecord.init(remote:))
        largeRecords = large.map(BenchmarkProjectRecord.init(remote:))
        smallBody = BenchmarkFixtures.responseBody(projects: small)
        largeBody = BenchmarkFixtures.responseBody(projects: large)
        largeCharacters = BenchmarkFixtures.characters(for: large)
        largeCharacterRecords = largeCharacters.map(BenchmarkCharacterRecord.init(remote:))
    }
}

private func makeAndroidJSONBenchmarks(_ fixtures: AndroidBenchmarkFixtures) -> [AndroidBenchmark] {
    [
        AndroidBenchmark(name: "android.foundation.jsondecoder.decode.1k", iterations: 40) {
            let projects = try fixtures.foundationDecoder.decode([BenchmarkProject].self, from: fixtures.smallBody)
            AndroidBlackHole.consume(projects.count)
        },
        AndroidBenchmark(name: "android.yyjson.decoder.decode.1k", iterations: 40) {
            let projects = try fixtures.yyjsonDecoder.decode([BenchmarkProject].self, from: fixtures.smallBody)
            AndroidBlackHole.consume(projects.count)
        },
        AndroidBenchmark(name: "android.koma.json.records.decode.1k", iterations: 40) {
            let records = try BenchmarkProjectRecord.komaJSONRecords(from: fixtures.smallBody)
            AndroidBlackHole.consume(records.count)
        },
        AndroidBenchmark(name: "android.foundation.jsondecoder.decode.10k", iterations: 20) {
            let projects = try fixtures.foundationDecoder.decode([BenchmarkProject].self, from: fixtures.largeBody)
            AndroidBlackHole.consume(projects.count)
        },
        AndroidBenchmark(name: "android.yyjson.decoder.decode.10k", iterations: 20) {
            let projects = try fixtures.yyjsonDecoder.decode([BenchmarkProject].self, from: fixtures.largeBody)
            AndroidBlackHole.consume(projects.count)
        },
        AndroidBenchmark(name: "android.koma.json.records.decode.10k", iterations: 20) {
            let records = try BenchmarkProjectRecord.komaJSONRecords(from: fixtures.largeBody)
            AndroidBlackHole.consume(records.count)
        },
        AndroidBenchmark(name: "android.foundation.jsonencoder.encode.1k", iterations: 40) {
            let body = try fixtures.foundationEncoder.encode(fixtures.small)
            AndroidBlackHole.consume(body.count)
        },
        AndroidBenchmark(name: "android.yyjson.encoder.encode.1k", iterations: 40) {
            let body = try fixtures.yyjsonEncoder.encode(fixtures.small)
            AndroidBlackHole.consume(body.count)
        },
        AndroidBenchmark(name: "android.koma.json.records.encode.1k", iterations: 40) {
            let body = try BenchmarkProjectRecord.komaJSONData(records: fixtures.smallRecords)
            AndroidBlackHole.consume(body.count)
        },
        AndroidBenchmark(name: "android.foundation.jsonencoder.encode.10k", iterations: 20) {
            let body = try fixtures.foundationEncoder.encode(fixtures.large)
            AndroidBlackHole.consume(body.count)
        },
        AndroidBenchmark(name: "android.yyjson.encoder.encode.10k", iterations: 20) {
            let body = try fixtures.yyjsonEncoder.encode(fixtures.large)
            AndroidBlackHole.consume(body.count)
        },
        AndroidBenchmark(name: "android.koma.json.records.encode.10k", iterations: 20) {
            let body = try BenchmarkProjectRecord.komaJSONData(records: fixtures.largeRecords)
            AndroidBlackHole.consume(body.count)
        }
    ]
}

private func makeAndroidSQLiteBenchmarks(_ fixtures: AndroidBenchmarkFixtures) -> [AndroidBenchmark] {
    let komaFetchStore = AndroidAsyncLazy {
        return try await seededKomaStore(
            label: "android-koma-fetch",
            records: fixtures.largeRecords
        )
    }
    let rawFetchDatabase = AndroidLazy {
        let database = try RawSQLiteBenchmarkDatabase(
            path: BenchmarkFixtures.databasePath("android-raw-fetch")
        )
        try database.upsert(fixtures.large)
        return database
    }
    let komaInnerJoinStore = makeSeededJoinStore(label: "android-koma-inner-join", fixtures: fixtures)
    let rawInnerJoinDatabase = makeSeededRawJoinDatabase(label: "android-raw-inner-join", fixtures: fixtures)
    let komaLeftJoinStore = makeSeededJoinStore(label: "android-koma-left-join", fixtures: fixtures)
    let rawLeftJoinDatabase = makeSeededRawJoinDatabase(label: "android-raw-left-join", fixtures: fixtures)

    return [
        AndroidBenchmark(name: "android.koma.sqlite.open.ensureSchema", iterations: 80) {
            let path = BenchmarkFixtures.databasePath("android-koma-open")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let store = try await SQLiteKomaStore(path: path)
            try await store.ensureSchema(for: BenchmarkProjectRecord.self)
            try await store.ensureSchema(for: BenchmarkCharacterRecord.self)
        },
        AndroidBenchmark(name: "android.rawsqlite.open.ensureSchema", iterations: 80) {
            let path = BenchmarkFixtures.databasePath("android-raw-open")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            _ = try RawSQLiteBenchmarkDatabase(path: path)
        },
        AndroidBenchmark(name: "android.koma.sqlite.batchUpsert.1k", iterations: 20) {
            let path = BenchmarkFixtures.databasePath("android-koma-upsert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let store = try await SQLiteKomaStore(path: path)
            try await store.upsert(fixtures.smallRecords)
        },
        AndroidBenchmark(name: "android.rawsqlite.batchUpsert.1k", iterations: 20) {
            let path = BenchmarkFixtures.databasePath("android-raw-upsert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try RawSQLiteBenchmarkDatabase(path: path)
            try database.upsert(fixtures.small)
        },
        AndroidBenchmark(name: "android.koma.sqlite.filteredOrderedFetch.10k.limit100", iterations: 20) {
            let store = try await komaFetchStore.get()
            let records =
                try await store
                    .query(BenchmarkProjectRecord.self)
                    .where { $0.deletedAt == nil }
                    .order(by: \.name)
                    .limit(100)
                    .fetch()
            AndroidBlackHole.consume(records.count)
        },
        AndroidBenchmark(name: "android.rawsqlite.filteredOrderedFetch.10k.limit100", iterations: 20) {
            let database = try rawFetchDatabase.get()
            let records = try database.fetchActiveProjects(limit: 100)
            AndroidBlackHole.consume(records.count)
        },
        AndroidBenchmark(name: "android.koma.sqlite.innerJoinFilter.10k.limit100", iterations: 20) {
            let store = try await komaInnerJoinStore.get()
            let records =
                try await store
                    .query(BenchmarkProjectRecord.self)
                    .join(BenchmarkCharacterRecord.self) { $0.id == $1.projectId }
                    .where { $0.deletedAt == nil }
                    .where(BenchmarkCharacterRecord.self) { $0.role == "lead" }
                    .order(by: \.name)
                    .limit(100)
                    .fetch()
            AndroidBlackHole.consume(records.count)
        },
        AndroidBenchmark(name: "android.rawsqlite.innerJoinFilter.10k.limit100", iterations: 20) {
            let database = try rawInnerJoinDatabase.get()
            let records = try database.fetchProjectsWithLeadCharacters(limit: 100)
            AndroidBlackHole.consume(records.count)
        },
        AndroidBenchmark(name: "android.koma.sqlite.leftJoinMissing.10k.limit100", iterations: 20) {
            let store = try await komaLeftJoinStore.get()
            let records =
                try await store
                    .query(BenchmarkProjectRecord.self)
                    .leftJoin(BenchmarkCharacterRecord.self) { $0.id == $1.projectId }
                    .where { $0.deletedAt == nil }
                    .where(BenchmarkCharacterRecord.self) { $0.id.isNull() }
                    .order(by: \.name)
                    .limit(100)
                    .fetch()
            AndroidBlackHole.consume(records.count)
        },
        AndroidBenchmark(name: "android.rawsqlite.leftJoinMissing.10k.limit100", iterations: 20) {
            let database = try rawLeftJoinDatabase.get()
            let records = try database.fetchProjectsWithoutCharacters(limit: 100)
            AndroidBlackHole.consume(records.count)
        }
    ]
}

private func makeSeededJoinStore(
    label: String,
    fixtures: AndroidBenchmarkFixtures
) -> AndroidAsyncLazy<SQLiteKomaStore> {
    AndroidAsyncLazy {
        let store = try await seededKomaStore(
            label: label,
            records: fixtures.largeRecords
        )
        try await store.upsert(fixtures.largeCharacterRecords)
        return store
    }
}

private func seededKomaStore(
    label: String,
    records: [BenchmarkProjectRecord]
) async throws -> SQLiteKomaStore {
    let store = try await SQLiteKomaStore(
        path: BenchmarkFixtures.databasePath(label)
    )
    try await store.upsert(records)
    return store
}

private func makeSeededRawJoinDatabase(
    label: String,
    fixtures: AndroidBenchmarkFixtures
) -> AndroidLazy<RawSQLiteBenchmarkDatabase> {
    AndroidLazy {
        let database = try RawSQLiteBenchmarkDatabase(
            path: BenchmarkFixtures.databasePath(label)
        )
        try database.upsert(fixtures.large)
        try database.upsertCharacters(fixtures.largeCharacters)
        return database
    }
}
