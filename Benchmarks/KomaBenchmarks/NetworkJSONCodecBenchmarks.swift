import Benchmark
import Foundation
import Koma
import KomaBenchmarkSupport
import YYJSON

func registerJSONCodecBenchmarks() {
    for payload in BenchmarkNetworkFixtures.payloads {
        Benchmark("network.foundation.jsondecoder.decode.\(payload.label)") { benchmark in
            let decoder = JSONDecoder()
            let body = payload.body

            for _ in benchmark.scaledIterations {
                let projects = try decoder.decode([BenchmarkProject].self, from: body)
                blackHole(projects.count)
            }
        }

        Benchmark("network.yyjson.decoder.decode.\(payload.label)") { benchmark in
            let decoder = YYJSONDecoder()
            let body = payload.body

            for _ in benchmark.scaledIterations {
                let projects = try decoder.decode([BenchmarkProject].self, from: body)
                blackHole(projects.count)
            }
        }

        Benchmark("network.koma.json.records.decode.\(payload.label)") { benchmark in
            let body = payload.body

            for _ in benchmark.scaledIterations {
                let records = try BenchmarkProjectRecord.komaJSONRecords(from: body)
                blackHole(records.count)
            }
        }

        Benchmark("network.foundation.jsonencoder.encode.\(payload.label)") { benchmark in
            let encoder = JSONEncoder()
            let projects = payload.projects

            for _ in benchmark.scaledIterations {
                let body = try encoder.encode(projects)
                blackHole(body.count)
            }
        }

        Benchmark("network.yyjson.encoder.encode.\(payload.label)") { benchmark in
            let encoder = YYJSONEncoder()
            let projects = payload.projects

            for _ in benchmark.scaledIterations {
                let body = try encoder.encode(projects)
                blackHole(body.count)
            }
        }

        Benchmark("network.koma.json.records.encode.\(payload.label)") { benchmark in
            let records = payload.projects.map(BenchmarkProjectRecord.init(remote:))

            for _ in benchmark.scaledIterations {
                let body = try BenchmarkProjectRecord.komaJSONData(records: records)
                blackHole(body.count)
            }
        }
    }
}
