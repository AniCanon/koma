import Foundation

func registerComparisonBenchmarks(small: [BenchmarkProject], large: [BenchmarkProject]) {
    registerGRDBBenchmarks(small: small, large: large)

    #if canImport(CoreData)
    registerCoreDataBenchmarks(small: small, large: large)
    #endif

    #if canImport(SwiftData)
    if #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) {
        registerSwiftDataBenchmarks(small: small, large: large)
    }
    #endif
}
