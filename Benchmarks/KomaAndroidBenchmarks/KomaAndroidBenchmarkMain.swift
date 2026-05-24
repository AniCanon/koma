import KomaAndroidBenchmarkCore

@main
@MainActor
enum KomaAndroidBenchmarkMain {
    static func main() async throws {
        try await AndroidBenchmarkRunner.run(
            makeKomaAndroidBenchmarks()
                + makeAndroidGRDBBenchmarks()
        )
    }
}
