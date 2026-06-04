import Foundation
import KomaBenchmarkSupport

func registerComparisonBenchmarks(small: [BenchmarkProject], large: [BenchmarkProject]) {
    #if KOMA_INCLUDE_GRDB_BENCHMARKS
    registerGRDBBenchmarks(small: small, large: large)
    registerGRDBMemoryBenchmarks()
    #endif

    #if canImport(CoreData)
    registerCoreDataBenchmarks(small: small, large: large)
    #endif

    // SwiftData's @Model macro plugin ships only with the Xcode toolchain, so the file is
    // excluded (and this call gated) unless KOMA_INCLUDE_SWIFTDATA_BENCHMARKS is set — see
    // Package.swift. canImport(SwiftData) is true on Apple platforms even when the macro
    // cannot expand, so it is not a sufficient gate on its own.
    #if KOMA_INCLUDE_SWIFTDATA_BENCHMARKS
    if #available(macOS 14, iOS 17, tvOS 17, watchOS 10, *) {
        registerSwiftDataBenchmarks(small: small, large: large)
    }
    #endif
}
