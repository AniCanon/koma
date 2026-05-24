import Dispatch
import Foundation
import KomaBenchmarkSupport
import YYJSON

private struct JSONBenchmark {
    let name: String
    let provider: String
    let operation: String
    let payload: String
    let iterations: Int
    let run: () throws -> Void
}

private struct Payload {
    let label: String
    let projects: [BenchmarkProject]
    let records: [BenchmarkProjectRecord]
    let body: Data
}

private struct Configuration {
    var filter: String?
    var iterations: Int?
    var warmupIterations = 3

    init(arguments: [String]) {
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
        guard let filter, !filter.isEmpty else {
            return true
        }
        return benchmarkName.range(of: filter, options: [.regularExpression]) != nil
    }

    func iterations(for benchmark: JSONBenchmark) -> Int {
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

@main
struct KomaJSONBenchmarkMain {
    static func main() throws {
        let configuration = Configuration(arguments: Array(CommandLine.arguments.dropFirst()))
        let benchmarks = makeBenchmarks().filter { configuration.includes($0.name) }

        guard !benchmarks.isEmpty else {
            print("No benchmarks matched filter: \(configuration.filter ?? "<none>")")
            return
        }

        print("# Koma JSON Benchmarks")
        print("")
        print("| Provider | Operation | Payload | p50 | p90 | p99 | Samples |")
        print("| --- | --- | ---: | ---: | ---: | ---: | ---: |")

        for benchmark in benchmarks {
            let samples = try run(benchmark, configuration: configuration)
            let percentiles = Percentiles(samples: samples)
            print(
                "| \(benchmark.provider) | \(benchmark.operation) | \(benchmark.payload) | "
                    + "\(format(percentiles.p50)) | \(format(percentiles.p90)) | "
                    + "\(format(percentiles.p99)) | \(samples.count) |"
            )
            print(
                "RESULT \(benchmark.name) p50_ns=\(percentiles.p50) p90_ns=\(percentiles.p90) p99_ns=\(percentiles.p99) samples=\(samples.count)"
            )
        }
    }

    private static func makeBenchmarks() -> [JSONBenchmark] {
        let payloads = [
            makePayload(label: "10", count: 10),
            makePayload(label: "1k", count: 1000),
            makePayload(label: "10k", count: 10000)
        ]
        let foundationDecoder = JSONDecoder()
        let foundationEncoder = JSONEncoder()
        let yyjsonDecoder = YYJSONDecoder()
        let yyjsonEncoder = YYJSONEncoder()

        return payloads.flatMap { payload in
            [
                JSONBenchmark(
                    name: "json.foundation.decode.\(payload.label)",
                    provider: "Foundation",
                    operation: "Decode",
                    payload: payload.label,
                    iterations: iterations(for: payload)
                ) {
                    let projects = try foundationDecoder.decode([BenchmarkProject].self, from: payload.body)
                    blackHole(projects.count)
                },
                JSONBenchmark(
                    name: "json.yyjson.decode.\(payload.label)",
                    provider: "YYJSON",
                    operation: "Decode",
                    payload: payload.label,
                    iterations: iterations(for: payload)
                ) {
                    let projects = try yyjsonDecoder.decode([BenchmarkProject].self, from: payload.body)
                    blackHole(projects.count)
                },
                JSONBenchmark(
                    name: "json.koma.records.decode.\(payload.label)",
                    provider: "Koma",
                    operation: "Record decode",
                    payload: payload.label,
                    iterations: iterations(for: payload)
                ) {
                    let records = try BenchmarkProjectRecord.komaJSONRecords(from: payload.body)
                    blackHole(records.count)
                },
                JSONBenchmark(
                    name: "json.foundation.encode.\(payload.label)",
                    provider: "Foundation",
                    operation: "Encode",
                    payload: payload.label,
                    iterations: iterations(for: payload)
                ) {
                    let body = try foundationEncoder.encode(payload.projects)
                    blackHole(body.count)
                },
                JSONBenchmark(
                    name: "json.yyjson.encode.\(payload.label)",
                    provider: "YYJSON",
                    operation: "Encode",
                    payload: payload.label,
                    iterations: iterations(for: payload)
                ) {
                    let body = try yyjsonEncoder.encode(payload.projects)
                    blackHole(body.count)
                },
                JSONBenchmark(
                    name: "json.koma.records.encode.\(payload.label)",
                    provider: "Koma",
                    operation: "Record encode",
                    payload: payload.label,
                    iterations: iterations(for: payload)
                ) {
                    let body = try BenchmarkProjectRecord.komaJSONData(records: payload.records)
                    blackHole(body.count)
                }
            ]
        }
    }

    private static func makePayload(label: String, count: Int) -> Payload {
        let projects = BenchmarkFixtures.projects(count)
        return Payload(
            label: label,
            projects: projects,
            records: projects.map(BenchmarkProjectRecord.init(remote:)),
            body: BenchmarkFixtures.responseBody(projects: projects)
        )
    }

    private static func iterations(for payload: Payload) -> Int {
        switch payload.label {
        case "10k":
            return 50
        case "1k":
            return 100
        default:
            return 300
        }
    }

    private static func run(_ benchmark: JSONBenchmark, configuration: Configuration) throws
        -> [UInt64]
    {
        for _ in 0 ..< configuration.warmupIterations {
            try benchmark.run()
        }

        var samples: [UInt64] = []
        samples.reserveCapacity(configuration.iterations(for: benchmark))

        for _ in 0 ..< configuration.iterations(for: benchmark) {
            let start = DispatchTime.now().uptimeNanoseconds
            try benchmark.run()
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private nonisolated(unsafe) var sink = 0

@inline(never)
private func blackHole(_ value: Int) {
    sink &+= value
}
