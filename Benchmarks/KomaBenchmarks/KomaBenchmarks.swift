import Benchmark
import Foundation
import Koma
import KomaBenchmarkSQLiteSupport
import KomaBenchmarkSupport
import KomaSQLite
import KomaTesting

let benchmarks: @Sendable () -> Void = {
    let small = BenchmarkFixtures.projects(1000)
    let large = BenchmarkFixtures.projects(10000)
    let smallRecords = small.map(BenchmarkProjectRecord.init(remote:))
    let largeRecords = large.map(BenchmarkProjectRecord.init(remote:))
    let largeCharacters = BenchmarkFixtures.characters(for: large)
    let largeCharacterRecords = largeCharacters.map(BenchmarkCharacterRecord.init(remote:))
    let smallResponse = BenchmarkFixtures.responseBody(projects: small)

    Benchmark("koma.sqlite.open.ensureSchema") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("koma-open")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let store = try await SQLiteKomaStore(path: path)
            try await store.ensureSchema(for: BenchmarkProjectRecord.self)
            blackHole(store)
        }
    }

    Benchmark("koma.sqlite.batchUpsert.1k") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("koma-upsert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let store = try await SQLiteKomaStore(path: path)
            try await store.upsert(smallRecords)
            blackHole(store)
        }
    }

    Benchmark("koma.sqlite.steadyUpsert.1k") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-steady-upsert")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)

        for _ in benchmark.scaledIterations {
            try await store.upsert(smallRecords)
        }

        blackHole(store)
    }

    Benchmark("koma.sqlite.fusedJSONUpsert.1k") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("koma-fused-json-upsert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let store = try await SQLiteKomaStore(path: path)
            try await store.upsertJSON(smallResponse, record: BenchmarkProjectRecord.self)
            blackHole(store)
        }
    }

    Benchmark("koma.sqlite.fusedJSONSteadyUpsert.1k") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-fused-json-steady-upsert")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)

        for _ in benchmark.scaledIterations {
            try await store.upsertJSON(smallResponse, record: BenchmarkProjectRecord.self)
        }

        blackHole(store)
    }

    Benchmark("koma.sqlite.observedUpsert.1k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-observed-upsert")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)
        let sink = BenchmarkObservationSink()
        let observation = Task {
            do {
                let stream = store
                    .query(BenchmarkProjectRecord.self)
                    .where { $0.deletedAt == nil }
                    .order(by: \.name)
                    .limit(100)
                    .observe()
                for try await records in stream {
                    await sink.record(records.count)
                }
            } catch {
                await sink.record(-1)
            }
        }

        _ = await sink.waitForCount(1)
        var expectedEmissions = 1

        for _ in benchmark.scaledIterations {
            try await store.upsert(smallRecords)
            expectedEmissions += 1
            _ = await sink.waitForCount(expectedEmissions)
        }

        observation.cancel()
        await blackHole(sink.latestCount())
    }

    Benchmark("rawsqlite.batchUpsert.1k") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("raw-upsert")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let database = try RawSQLiteBenchmarkDatabase(path: path)
            try database.upsert(small)
            blackHole(database)
        }
    }

    Benchmark("koma.sqlite.filteredOrderedFetch.10k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-fetch")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)
        try await store.upsert(largeRecords)

        for _ in benchmark.scaledIterations {
            let records = try await store
                .query(BenchmarkProjectRecord.self)
                .where { $0.deletedAt == nil }
                .order(by: \.name)
                .limit(100)
                .fetch()
            blackHole(records.count)
        }
    }

    Benchmark("rawsqlite.filteredOrderedFetch.10k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("raw-fetch")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let database = try RawSQLiteBenchmarkDatabase(path: path)
        try database.upsert(large)

        for _ in benchmark.scaledIterations {
            let records = try database.fetchActiveProjects(limit: 100)
            blackHole(records.count)
        }
    }

    Benchmark("koma.sqlite.innerJoinFilter.10k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-inner-join")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)
        try await store.upsert(largeRecords)
        try await store.upsert(largeCharacterRecords)

        for _ in benchmark.scaledIterations {
            let records = try await store
                .query(BenchmarkProjectRecord.self)
                .join(BenchmarkCharacterRecord.self) { $0.id == $1.projectId }
                .where { $0.deletedAt == nil }
                .where(BenchmarkCharacterRecord.self) { $0.role == "lead" }
                .order(by: \.name)
                .limit(100)
                .fetch()
            blackHole(records.count)
        }
    }

    Benchmark("rawsqlite.innerJoinFilter.10k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("raw-inner-join")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let database = try RawSQLiteBenchmarkDatabase(path: path)
        try database.upsert(large)
        try database.upsertCharacters(largeCharacters)

        for _ in benchmark.scaledIterations {
            let records = try database.fetchProjectsWithLeadCharacters(limit: 100)
            blackHole(records.count)
        }
    }

    Benchmark("koma.sqlite.rightJoinMatched.10k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-right-join")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)
        try await store.upsert(largeRecords)
        try await store.upsert(largeCharacterRecords)

        for _ in benchmark.scaledIterations {
            let records = try await store
                .query(BenchmarkProjectRecord.self)
                .rightJoin(BenchmarkCharacterRecord.self) { $0.id == $1.projectId }
                .where { $0.id.isNotNull() }
                .where { $0.deletedAt == nil }
                .where(BenchmarkCharacterRecord.self) { $0.role == "lead" }
                .order(by: \.name)
                .limit(100)
                .fetch()
            blackHole(records.count)
        }
    }

    Benchmark("rawsqlite.rightJoinMatched.10k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("raw-right-join")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let database = try RawSQLiteBenchmarkDatabase(path: path)
        try database.upsert(large)
        try database.upsertCharacters(largeCharacters)

        for _ in benchmark.scaledIterations {
            let records = try database.fetchProjectsRightJoinedToLeadCharacters(limit: 100)
            blackHole(records.count)
        }
    }

    Benchmark("koma.sqlite.leftJoinMissing.10k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-left-join")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)
        try await store.upsert(largeRecords)
        try await store.upsert(largeCharacterRecords)

        for _ in benchmark.scaledIterations {
            let records = try await store
                .query(BenchmarkProjectRecord.self)
                .leftJoin(BenchmarkCharacterRecord.self) { $0.id == $1.projectId }
                .where { $0.deletedAt == nil }
                .where(BenchmarkCharacterRecord.self) { $0.id.isNull() }
                .order(by: \.name)
                .limit(100)
                .fetch()
            blackHole(records.count)
        }
    }

    Benchmark("rawsqlite.leftJoinMissing.10k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("raw-left-join")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let database = try RawSQLiteBenchmarkDatabase(path: path)
        try database.upsert(large)
        try database.upsertCharacters(largeCharacters)

        for _ in benchmark.scaledIterations {
            let records = try database.fetchProjectsWithoutCharacters(limit: 100)
            blackHole(records.count)
        }
    }

    Benchmark("koma.resource.networkFirstFallback.1k") { benchmark in
        for _ in benchmark.scaledIterations {
            let path = BenchmarkFixtures.databasePath("koma-resource")
            defer { BenchmarkFixtures.removeDatabaseFiles(path) }

            let store = try await SQLiteKomaStore(path: path)
            let transport = FakeKomaTransport(
                responses: [
                    KomaResponse(statusCode: 200, body: smallResponse)
                ]
            )
            let koma = KomaClient(
                baseURL: URL(string: "https://benchmark.invalid")!,
                store: store,
                transport: transport
            )

            let snapshot = try await BenchmarkProjectResources
                .client(in: koma)
                .list()
                .where { $0.deletedAt == nil }
                .order(by: \.name)
                .fetch(policy: .networkFirstFallback)
            blackHole(snapshot.value.count)
        }
    }

    Benchmark("koma.resource.localOnly.10k.limit100") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-local-only")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)
        try await store.upsert(largeRecords)
        let transport = FakeKomaTransport()
        let koma = KomaClient(
            baseURL: URL(string: "https://benchmark.invalid")!,
            store: store,
            transport: transport
        )

        for _ in benchmark.scaledIterations {
            let snapshot = try await BenchmarkProjectResources
                .client(in: koma)
                .list()
                .where { $0.deletedAt == nil }
                .order(by: \.name)
                .limit(100)
                .fetch(policy: .localOnly)
            blackHole(snapshot.value.count)
        }
    }

    registerComparisonBenchmarks(small: small, large: large)
    registerNetworkBenchmarks()
}

private actor BenchmarkObservationSink {
    private var emissionCount = 0
    private var latest = 0
    private var waiters: [(count: Int, continuation: CheckedContinuation<Int, Never>)] = []

    func record(_ count: Int) {
        emissionCount += 1
        latest = count
        resumeSatisfiedWaiters()
    }

    func waitForCount(_ count: Int) async -> Int {
        if emissionCount >= count {
            return latest
        }

        return await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func latestCount() -> Int {
        latest
    }

    private func resumeSatisfiedWaiters() {
        var remaining: [(count: Int, continuation: CheckedContinuation<Int, Never>)] = []
        for waiter in waiters {
            if emissionCount >= waiter.count {
                waiter.continuation.resume(returning: latest)
            } else {
                remaining.append(waiter)
            }
        }
        waiters = remaining
    }
}
