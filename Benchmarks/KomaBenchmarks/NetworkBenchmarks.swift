import Alamofire
import Apollo
import Benchmark
import Foundation
import Koma
import KomaHTTP
import KomaSQLite
import Moya

func registerNetworkBenchmarks() {
    let restURL = BenchmarkNetworkFixtures.payload1k.url
    let graphQLURL = BenchmarkNetworkFixtures.baseURL.appendingPathComponent("graphql")

    for payload in BenchmarkNetworkFixtures.payloads {
        Benchmark("network.foundation.jsondecoder.decode.\(payload.label)") { benchmark in
            let decoder = JSONDecoder()
            let body = payload.body

            for _ in benchmark.scaledIterations {
                let projects = try decoder.decode([BenchmarkProject].self, from: body)
                blackHole(projects.count)
            }
        }

        Benchmark("network.koma.json.records.decode.\(payload.label)") { benchmark in
            let body = payload.body

            for _ in benchmark.scaledIterations {
                let records = try BenchmarkProjectRecord._komaJSONRecords(from: body)
                blackHole(records.count)
            }
        }

        Benchmark("network.urlsession.get.data.\(payload.label)") { benchmark in
            let session = BenchmarkNetworkFixtures.urlSession()
            let url = payload.url

            for _ in benchmark.scaledIterations {
                let (data, _) = try await session.data(from: url)
                blackHole(data.count)
            }
        }

        Benchmark("network.urlsession.get.decode.\(payload.label)") { benchmark in
            let session = BenchmarkNetworkFixtures.urlSession()
            let decoder = JSONDecoder()
            let url = payload.url

            for _ in benchmark.scaledIterations {
                let (data, _) = try await session.data(from: url)
                let projects = try decoder.decode([BenchmarkProject].self, from: data)
                blackHole(projects.count)
            }
        }

        Benchmark("network.koma.transport.get.jsonrecord.\(payload.label)") { benchmark in
            let session = BenchmarkNetworkFixtures.urlSession()
            let koma = KomaClient(
                baseURL: BenchmarkNetworkFixtures.baseURL,
                store: BenchmarkNoopStore(),
                session: session
            )
            let request = KomaRequest(method: .get, path: payload.path)

            for _ in benchmark.scaledIterations {
                let response = try await koma.execute(
                    request,
                    operation: "benchmark.projects.network",
                    collectResponseHeaders: false
                )
                let records = try BenchmarkProjectRecord._komaJSONRecords(from: response.body)
                blackHole(records.count)
            }
        }
    }

    Benchmark("network.koma.transport.get.decode.1k") { benchmark in
        let session = BenchmarkNetworkFixtures.urlSession()
        let koma = KomaClient(
            baseURL: BenchmarkNetworkFixtures.baseURL,
            store: BenchmarkNoopStore(),
            session: session
        )
        let decoder = JSONDecoder()
        let request = KomaRequest(method: .get, path: "projects")

        for _ in benchmark.scaledIterations {
            let response = try await koma.execute(
                request,
                operation: "benchmark.projects.network",
                collectResponseHeaders: false
            )
            let projects = try decoder.decode([BenchmarkProject].self, from: response.body)
            blackHole(projects.count)
        }
    }

    Benchmark("network.koma.transport.get.decode.headers.1k") { benchmark in
        let session = BenchmarkNetworkFixtures.urlSession()
        let koma = KomaClient(
            baseURL: BenchmarkNetworkFixtures.baseURL,
            store: BenchmarkNoopStore(),
            session: session
        )
        let decoder = JSONDecoder()
        let request = KomaRequest(method: .get, path: "projects")

        for _ in benchmark.scaledIterations {
            let response = try await koma.execute(request, operation: "benchmark.projects.network")
            let projects = try decoder.decode([BenchmarkProject].self, from: response.body)
            blackHole(projects.count)
        }
    }

    Benchmark("network.koma.transport.get.data.1k") { benchmark in
        let session = BenchmarkNetworkFixtures.urlSession()
        let koma = KomaClient(
            baseURL: BenchmarkNetworkFixtures.baseURL,
            store: BenchmarkNoopStore(),
            session: session
        )
        let request = KomaRequest(method: .get, path: "projects")

        for _ in benchmark.scaledIterations {
            let response = try await koma.execute(
                request,
                operation: "benchmark.projects.network",
                collectResponseHeaders: false
            )
            blackHole(response.body.count)
        }
    }

    Benchmark("network.koma.resource.urlsession.networkFirstFallback.1k") { benchmark in
        let path = BenchmarkFixtures.databasePath("koma-network-resource")
        defer { BenchmarkFixtures.removeDatabaseFiles(path) }

        let store = try await SQLiteKomaStore(path: path)
        let session = BenchmarkNetworkFixtures.urlSession()
        let koma = KomaClient(
            baseURL: BenchmarkNetworkFixtures.baseURL,
            store: store,
            session: session
        )

        for _ in benchmark.scaledIterations {
            let snapshot = try await BenchmarkProjectResources
                .client(in: koma)
                .list()
                .where { $0.deletedAt == nil }
                .order(by: \.name)
                .fetch(policy: .networkFirstFallback)
            blackHole(snapshot.value.count)
        }
    }

    Benchmark("network.alamofire.get.decode.1k") { benchmark in
        let session = Alamofire.Session(configuration: BenchmarkNetworkFixtures.urlSessionConfiguration())

        for _ in benchmark.scaledIterations {
            let projects = try await session
                .request(restURL)
                .serializingDecodable([BenchmarkProject].self)
                .value
            blackHole(projects.count)
        }
    }

    Benchmark("network.moya.get.decode.1k") { benchmark in
        let session = Alamofire.Session(configuration: BenchmarkNetworkFixtures.urlSessionConfiguration())
        let provider = MoyaProvider<BenchmarkMoyaTarget>(
            callbackQueue: DispatchQueue(label: "org.anicanon.koma.benchmark.moya"),
            session: session
        )
        let decoder = JSONDecoder()

        for _ in benchmark.scaledIterations {
            let data = try await provider.requestData(.projects)
            let projects = try decoder.decode([BenchmarkProject].self, from: data)
            blackHole(projects.count)
        }
    }

    Benchmark("network.apollo.query.networkOnly.1k") { benchmark in
        let session = BenchmarkNetworkFixtures.urlSession()
        let store = ApolloStore(cache: InMemoryNormalizedCache())
        let transport = RequestChainNetworkTransport(
            urlSession: session,
            interceptorProvider: DefaultInterceptorProvider.shared,
            store: store,
            endpointURL: graphQLURL
        )
        let client = ApolloClient(
            networkTransport: transport,
            store: store,
            defaultRequestConfiguration: RequestConfiguration(writeResultsToCache: false)
        )

        for _ in benchmark.scaledIterations {
            let response = try await client.fetch(
                query: BenchmarkProjectsQuery(),
                cachePolicy: .networkOnly
            )
            blackHole(response.data?.projects.count ?? 0)
        }
    }
}
