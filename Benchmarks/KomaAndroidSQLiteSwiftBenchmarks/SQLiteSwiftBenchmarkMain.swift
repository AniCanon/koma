import KomaAndroidBenchmarkCore

@main
@MainActor
enum SQLiteSwiftBenchmarkMain {
    static func main() async throws {
        try await AndroidBenchmarkRunner.run(makeSQLiteSwiftBenchmarks())
    }
}
