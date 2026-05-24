import Foundation
import Koma
import KomaAndroidBenchmarkCore
import KomaBenchmarkSQLiteSupport
import KomaBenchmarkSupport
import KomaSQLite

func makeKomaAndroidBenchmarks() -> [AndroidBenchmark] {
    let small = BenchmarkFixtures.projects(1000)
    let large = BenchmarkFixtures.projects(10000)
    let smallRecords = small.map(BenchmarkProjectRecord.init(remote:))
    let largeRecords = large.map(BenchmarkProjectRecord.init(remote:))
    let largeCharacters = BenchmarkFixtures.characters(for: large)
    let largeCharacterRecords = largeCharacters.map(BenchmarkCharacterRecord.init(remote:))
    let komaFetchStore = AndroidAsyncLazy {
        let store = try await SQLiteKomaStore(path: BenchmarkFixtures.databasePath("android-koma-fetch"))
        try await store.upsert(largeRecords)
        return store
    }
    let rawFetchDatabase = AndroidLazy {
        let database = try RawSQLiteBenchmarkDatabase(path: BenchmarkFixtures.databasePath("android-raw-fetch"))
        try database.upsert(large)
        return database
    }
    let komaInnerJoinStore = AndroidAsyncLazy {
        let store = try await SQLiteKomaStore(path: BenchmarkFixtures.databasePath("android-koma-inner-join"))
        try await store.upsert(largeRecords)
        try await store.upsert(largeCharacterRecords)
        return store
    }
    let rawInnerJoinDatabase = AndroidLazy {
        let database = try RawSQLiteBenchmarkDatabase(path: BenchmarkFixtures.databasePath("android-raw-inner-join"))
        try database.upsert(large)
        try database.upsertCharacters(largeCharacters)
        return database
    }
    let komaLeftJoinStore = AndroidAsyncLazy {
        let store = try await SQLiteKomaStore(path: BenchmarkFixtures.databasePath("android-koma-left-join"))
        try await store.upsert(largeRecords)
        try await store.upsert(largeCharacterRecords)
        return store
    }
    let rawLeftJoinDatabase = AndroidLazy {
        let database = try RawSQLiteBenchmarkDatabase(path: BenchmarkFixtures.databasePath("android-raw-left-join"))
        try database.upsert(large)
        try database.upsertCharacters(largeCharacters)
        return database
    }

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
            try await store.upsert(smallRecords)
        },
        AndroidBenchmark(name: "android.rawsqlite.batchUpsert.1k", iterations: 20) {
            let path = BenchmarkFixtures.databasePath("android-raw-upsert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try RawSQLiteBenchmarkDatabase(path: path)
            try database.upsert(small)
        },
        AndroidBenchmark(name: "android.koma.sqlite.filteredOrderedFetch.10k.limit100", iterations: 20) {
            let store = try await komaFetchStore.get()
            let records = try await store
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
            let records = try await store
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
            let records = try await store
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
