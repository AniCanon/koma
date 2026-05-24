import Koma
import KomaBenchmarkSupport

enum BenchmarkProjectResources: KomaResourceNamespace {
    struct Client {
        private let koma: KomaClient

        init(koma: KomaClient) {
            self.koma = koma
        }

        func list() -> KomaFetch<[BenchmarkProject], BenchmarkProjectRecord> {
            KomaFetch(
                client: koma,
                operation: KomaOperation(
                    name: "benchmark.projects.list",
                    method: .get,
                    path: "projects",
                    cache: .collection("benchmark-projects", staleAfter: .minutes(5))
                ),
                output: [BenchmarkProject].self,
                record: BenchmarkProjectRecord.self
            )
        }
    }

    static func client(in koma: KomaClient) -> Client {
        Client(koma: koma)
    }
}
