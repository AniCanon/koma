import Foundation
import KomaBenchmarkSupport

func registerComparisonBenchmarks(small: [BenchmarkProject], large: [BenchmarkProject]) {
    #if KOMA_INCLUDE_GRDB_BENCHMARKS
    registerGRDBBenchmarks(small: small, large: large)
    #endif

    #if canImport(CoreData)
    registerCoreDataBenchmarks(small: small, large: large)
    #endif

    #if canImport(SwiftData)
    if #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) {
        registerSwiftDataBenchmarks(small: small, large: large)
    }
    #endif
}
