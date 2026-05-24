import KomaAndroidBenchmarkCore

@main
@MainActor
enum KomaAndroidBenchmarkMain {
    static func main() async throws {
        var benchmarks = makeKomaAndroidBenchmarks()

        #if KOMA_INCLUDE_GRDB_BENCHMARKS
        benchmarks += makeAndroidGRDBBenchmarks()
        #endif

        try await AndroidBenchmarkRunner.run(benchmarks)
    }
}
