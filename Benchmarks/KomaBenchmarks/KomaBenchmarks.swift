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

    // Change-guarded upserts skip identical rows entirely, so steady benchmarks alternate
    // between two payload variants to keep every iteration writing real changes; the
    // noChange benchmarks measure the skip path explicitly.
    let smallVariant = small.map { project in
        BenchmarkProject(
            id: project.id,
            name: project.name,
            slug: project.slug,
            deletedAt: project.deletedAt,
            score: project.score + 1,
            updatedAt: project.updatedAt,
            summary: project.summary
        )
    }
    let smallVariantRecords = smallVariant.map(BenchmarkProjectRecord.init(remote:))
    let smallVariantResponse = BenchmarkFixtures.responseBody(projects: smallVariant)

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

        for iteration in benchmark.scaledIterations {
            try await store.upsert(iteration.isMultiple(of: 2) ? smallRecords : smallVariantRecords)
        }

        blackHole(store)
    }

    Benchmark("koma.sqlite.noChangeUpsert.1k") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-nochange-upsert")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)
        try await store.upsert(smallRecords)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try await store.upsert(smallRecords)
        }
        benchmark.stopMeasurement()

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

        for iteration in benchmark.scaledIterations {
            try await store.upsertJSON(
                iteration.isMultiple(of: 2) ? smallResponse : smallVariantResponse,
                record: BenchmarkProjectRecord.self
            )
        }

        blackHole(store)
    }

    Benchmark("koma.sqlite.fusedJSONNoChangeUpsert.1k") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-fused-json-nochange-upsert")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)
        try await store.upsertJSON(smallResponse, record: BenchmarkProjectRecord.self)

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            try await store.upsertJSON(smallResponse, record: BenchmarkProjectRecord.self)
        }
        benchmark.stopMeasurement()

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

        for iteration in benchmark.scaledIterations {
            // Alternate payloads so every upsert really changes rows; identical payloads are
            // change-guarded no-ops that fire no observation at all.
            try await store.upsert(iteration.isMultiple(of: 2) ? smallRecords : smallVariantRecords)
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
        let store = try await BenchmarkFixtureCache.shared.value("koma-fetch") {
            let path = BenchmarkFixtures.databasePath("koma-fetch")
            let store = try await SQLiteKomaStore(path: path)
            try await store.upsert(largeRecords)
            return store
        }

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let records = try await store
                .query(BenchmarkProjectRecord.self)
                .where { $0.deletedAt == nil }
                .order(by: \.name)
                .limit(100)
                .fetch()
            blackHole(records.count)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("rawsqlite.filteredOrderedFetch.10k.limit100") { benchmark in
        let database = try await BenchmarkFixtureCache.shared.value("raw-fetch") {
            let path = BenchmarkFixtures.databasePath("raw-fetch")
            let database = try RawSQLiteBenchmarkDatabase(path: path)
            try database.upsert(large)
            return database
        }

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let records = try database.fetchActiveProjects(limit: 100)
            blackHole(records.count)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("koma.sqlite.innerJoinFilter.10k.limit100") { benchmark in
        let store = try await BenchmarkFixtureCache.shared.value("koma-inner-join") {
            let path = BenchmarkFixtures.databasePath("koma-inner-join")
            let store = try await SQLiteKomaStore(path: path)
            try await store.upsert(largeRecords)
            try await store.upsert(largeCharacterRecords)
            return store
        }

        benchmark.startMeasurement()
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
        benchmark.stopMeasurement()
    }

    Benchmark("rawsqlite.innerJoinFilter.10k.limit100") { benchmark in
        let database = try await BenchmarkFixtureCache.shared.value("raw-inner-join") {
            let path = BenchmarkFixtures.databasePath("raw-inner-join")
            let database = try RawSQLiteBenchmarkDatabase(path: path)
            try database.upsert(large)
            try database.upsertCharacters(largeCharacters)
            return database
        }

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let records = try database.fetchProjectsWithLeadCharacters(limit: 100)
            blackHole(records.count)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("koma.sqlite.rightJoinMatched.10k.limit100") { benchmark in
        let store = try await BenchmarkFixtureCache.shared.value("koma-right-join") {
            let path = BenchmarkFixtures.databasePath("koma-right-join")
            let store = try await SQLiteKomaStore(path: path)
            try await store.upsert(largeRecords)
            try await store.upsert(largeCharacterRecords)
            return store
        }

        benchmark.startMeasurement()
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
        benchmark.stopMeasurement()
    }

    Benchmark("rawsqlite.rightJoinMatched.10k.limit100") { benchmark in
        let database = try await BenchmarkFixtureCache.shared.value("raw-right-join") {
            let path = BenchmarkFixtures.databasePath("raw-right-join")
            let database = try RawSQLiteBenchmarkDatabase(path: path)
            try database.upsert(large)
            try database.upsertCharacters(largeCharacters)
            return database
        }

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let records = try database.fetchProjectsRightJoinedToLeadCharacters(limit: 100)
            blackHole(records.count)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("koma.sqlite.leftJoinMissing.10k.limit100") { benchmark in
        let store = try await BenchmarkFixtureCache.shared.value("koma-left-join") {
            let path = BenchmarkFixtures.databasePath("koma-left-join")
            let store = try await SQLiteKomaStore(path: path)
            try await store.upsert(largeRecords)
            try await store.upsert(largeCharacterRecords)
            return store
        }

        benchmark.startMeasurement()
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
        benchmark.stopMeasurement()
    }

    Benchmark("rawsqlite.leftJoinMissing.10k.limit100") { benchmark in
        let database = try await BenchmarkFixtureCache.shared.value("raw-left-join") {
            let path = BenchmarkFixtures.databasePath("raw-left-join")
            let database = try RawSQLiteBenchmarkDatabase(path: path)
            try database.upsert(large)
            try database.upsertCharacters(largeCharacters)
            return database
        }

        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            let records = try database.fetchProjectsWithoutCharacters(limit: 100)
            blackHole(records.count)
        }
        benchmark.stopMeasurement()
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
        let store = try await BenchmarkFixtureCache.shared.value("koma-local-only") {
            let path = BenchmarkFixtures.databasePath("koma-local-only")
            let store = try await SQLiteKomaStore(path: path)
            try await store.upsert(largeRecords)
            return store
        }
        let koma = KomaClient(
            baseURL: URL(string: "https://benchmark.invalid")!,
            store: store,
            transport: FakeKomaTransport()
        )

        benchmark.startMeasurement()
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
        benchmark.stopMeasurement()
    }

    Benchmark("koma.sqlite.pointRead.10k") { benchmark in
        let store = try await BenchmarkFixtureCache.shared.value("koma-point-read") {
            let path = BenchmarkFixtures.databasePath("koma-point-read")
            let store = try await SQLiteKomaStore(path: path)
            try await store.upsert(largeRecords)
            return store
        }

        benchmark.startMeasurement()
        for iteration in benchmark.scaledIterations {
            let id = "project-\((iteration &* 2_654_435_761) % 10000)"
            let records = try await store
                .query(BenchmarkProjectRecord.self)
                .where { $0.id == id }
                .limit(1)
                .fetch()
            blackHole(records.count)
        }
        benchmark.stopMeasurement()
    }

    Benchmark("rawsqlite.pointRead.10k") { benchmark in
        let database = try await BenchmarkFixtureCache.shared.value("raw-point-read") {
            let path = BenchmarkFixtures.databasePath("raw-point-read")
            let database = try RawSQLiteBenchmarkDatabase(path: path)
            try database.upsert(large)
            return database
        }

        benchmark.startMeasurement()
        for iteration in benchmark.scaledIterations {
            let id = "project-\((iteration &* 2_654_435_761) % 10000)"
            try blackHole(database.fetchProject(id: id))
        }
        benchmark.stopMeasurement()
    }

    Benchmark("koma.sqlite.pointUpsert.10k") { benchmark in
        let store = try await BenchmarkFixtureCache.shared.value("koma-point-upsert") {
            let path = BenchmarkFixtures.databasePath("koma-point-upsert")
            let store = try await SQLiteKomaStore(path: path)
            try await store.upsert(largeRecords)
            return store
        }

        benchmark.startMeasurement()
        for iteration in benchmark.scaledIterations {
            // The score changes every iteration so the write is never a change-guarded no-op.
            var record = largeRecords[(iteration &* 2_654_435_761) % 10000]
            record.score = iteration
            try await store.upsert([record])
        }
        benchmark.stopMeasurement()
    }

    Benchmark("koma.sqlite.concurrentReadDuringWrite.10k.limit100") { benchmark in
        let store = try await BenchmarkFixtureCache.shared.value("koma-concurrent-read") {
            let path = BenchmarkFixtures.databasePath("koma-concurrent-read")
            let store = try await SQLiteKomaStore(path: path)
            try await store.upsert(largeRecords)
            return store
        }

        benchmark.startMeasurement()
        for iteration in benchmark.scaledIterations {
            // One 1k batch write runs while four limit-100 reads complete; pooled reads
            // overlap the write instead of queueing behind it.
            async let write: Void = store.upsert(
                iteration.isMultiple(of: 2) ? smallRecords : smallVariantRecords
            )
            try await withThrowingTaskGroup(of: Int.self) { group in
                for _ in 0 ..< 4 {
                    group.addTask {
                        try await store
                            .query(BenchmarkProjectRecord.self)
                            .where { $0.deletedAt == nil }
                            .order(by: \.name)
                            .limit(100)
                            .fetch()
                            .count
                    }
                }
                for try await count in group {
                    blackHole(count)
                }
            }
            try await write
        }
        benchmark.stopMeasurement()
    }

    registerComparisonBenchmarks(small: small, large: large)
    registerNetworkBenchmarks()
    registerHybridSearchBenchmarks()
    registerHybridSearchFloat32Benchmarks()
    registerRawSQLiteMemoryBenchmarks()
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
