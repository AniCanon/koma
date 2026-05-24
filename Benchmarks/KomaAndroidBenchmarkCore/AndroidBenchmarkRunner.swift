import Dispatch
import Foundation

public struct AndroidBenchmark {
    public let name: String
    public let iterations: Int
    public let run: () async throws -> Void

    public init(
        name: String,
        iterations: Int,
        run: @escaping () async throws -> Void
    ) {
        self.name = name
        self.iterations = iterations
        self.run = run
    }
}

@MainActor
public enum AndroidBenchmarkRunner {
    public static func run(_ benchmarks: [AndroidBenchmark]) async throws {
        let configuration = try AndroidBenchmarkConfiguration(arguments: Array(CommandLine.arguments.dropFirst()))
        let selected = benchmarks.filter { configuration.includes($0.name) }
        guard !selected.isEmpty else {
            print("No benchmarks matched filter: \(configuration.filter ?? "<none>")")
            return
        }

        print("# Koma Android Benchmarks")
        print("")
        print("| Benchmark | p50 | p90 | p99 | Samples |")
        print("| --- | ---: | ---: | ---: | ---: |")

        for benchmark in selected {
            let samples = try await run(benchmark, configuration: configuration)
            let percentiles = Percentiles(samples: samples)
            print(
                "| `\(benchmark.name)` | \(format(percentiles.p50)) | \(format(percentiles.p90)) | \(format(percentiles.p99)) | \(samples.count) |"
            )
            print(
                "RESULT \(benchmark.name) p50_ns=\(percentiles.p50) p90_ns=\(percentiles.p90) p99_ns=\(percentiles.p99) samples=\(samples.count)"
            )
        }
    }

    private static func run(
        _ benchmark: AndroidBenchmark,
        configuration: AndroidBenchmarkConfiguration
    ) async throws -> [UInt64] {
        for _ in 0 ..< configuration.warmupIterations {
            try await benchmark.run()
        }

        var samples: [UInt64] = []
        samples.reserveCapacity(configuration.iterations(for: benchmark))

        for _ in 0 ..< configuration.iterations(for: benchmark) {
            let start = DispatchTime.now().uptimeNanoseconds
            try await benchmark.run()
            samples.append(DispatchTime.now().uptimeNanoseconds - start)
        }

        return samples.sorted()
    }

    private static func format(_ nanoseconds: UInt64) -> String {
        if nanoseconds >= 1_000_000 {
            return String(format: "%.3f ms", Double(nanoseconds) / 1_000_000)
        }
        if nanoseconds >= 1000 {
            return String(format: "%.3f us", Double(nanoseconds) / 1000)
        }
        return "\(nanoseconds) ns"
    }
}

struct AndroidBenchmarkConfiguration {
    var filter: String?
    var iterations: Int?
    var warmupIterations = 2

    init(arguments: [String]) throws {
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            switch argument {
            case "--filter":
                index = arguments.index(after: index)
                filter = arguments[safe: index]
            case "--iterations":
                index = arguments.index(after: index)
                iterations = arguments[safe: index].flatMap(Int.init)
            case "--warmup":
                index = arguments.index(after: index)
                warmupIterations = arguments[safe: index].flatMap(Int.init) ?? warmupIterations
            default:
                break
            }
            index = arguments.index(after: index)
        }
    }

    func includes(_ benchmarkName: String) -> Bool {
        guard let filter,
              !filter.isEmpty
        else {
            return true
        }
        return benchmarkName.range(of: filter, options: [.regularExpression]) != nil
    }

    func iterations(for benchmark: AndroidBenchmark) -> Int {
        iterations ?? benchmark.iterations
    }
}

private struct Percentiles {
    let p50: UInt64
    let p90: UInt64
    let p99: UInt64

    init(samples: [UInt64]) {
        p50 = Self.value(in: samples, percentile: 50)
        p90 = Self.value(in: samples, percentile: 90)
        p99 = Self.value(in: samples, percentile: 99)
    }

    private static func value(in samples: [UInt64], percentile: Int) -> UInt64 {
        guard !samples.isEmpty else {
            return 0
        }
        let index = min(samples.count - 1, (samples.count * percentile) / 100)
        return samples[index]
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public enum AndroidBlackHole {
    private nonisolated(unsafe) static var integerSink = 0

    @inline(never)
    public static func consume(_ value: Int) {
        integerSink &+= value
    }
}

public final class AndroidAsyncLazy<Value> {
    private var value: Value?
    private let makeValue: () async throws -> Value

    public init(_ makeValue: @escaping () async throws -> Value) {
        self.makeValue = makeValue
    }

    public func get() async throws -> Value {
        if let value {
            return value
        }
        let value = try await makeValue()
        self.value = value
        return value
    }
}

public final class AndroidLazy<Value> {
    private var value: Value?
    private let makeValue: () throws -> Value

    public init(_ makeValue: @escaping () throws -> Value) {
        self.makeValue = makeValue
    }

    public func get() throws -> Value {
        if let value {
            return value
        }
        let value = try makeValue()
        self.value = value
        return value
    }
}
