# App Startup

Create Koma once at the app boundary, then inject the client into repositories or expose app-specific methods from your shared Swift layer.

## iOS

For iOS, use the platform application support directory. This keeps the database path stable across launches and lets Koma create the parent directory.

```swift
@main
struct AniCanonApp: App {
    @State private var koma: KomaClient?
    @State private var startupErrorMessage: String?

    var body: some Scene {
        WindowGroup {
            if let koma {
                ProjectListView(repository: ProjectRepository(koma: koma))
            } else if let startupErrorMessage {
                Text(startupErrorMessage)
            } else {
                ProgressView()
                    .task {
                        do {
                            koma = try await AppRuntime.makeKoma(
                                tokenProvider: AppTokenProvider()
                            )
                        } catch {
                            startupErrorMessage = error.localizedDescription
                        }
                    }
            }
        }
    }
}

enum AppRuntime {
    static func makeKoma(
        tokenProvider: any TokenProvider
    ) async throws -> KomaClient {
        try await KomaClient.sqlite(
            database: .applicationSupport("AniCanon.sqlite", appDirectory: "AniCanon"),
            schema: KomaSchema(modules: [
                ProjectSchema.self,
                CharacterSchema.self
            ]),
            baseURL: URL(string: "https://api.example.com/v1")!,
            plugins: [
                KomaBearerAuthPlugin { try await tokenProvider.token() },
                KomaRetryPlugin(maxAttempts: 2)
            ]
        )
    }
}
```

This keeps app initialization nonblocking. If you prefer a blocking splash flow, await Koma creation before presenting the main app surface.

## Android Swift

Android owns the sandbox path. Pass that path from Kotlin into the shared Swift layer, then create Koma with `.path(...)`.

```kotlin
class AniCanonApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        val databaseFile = getDatabasePath("koma.sqlite")
        databaseFile.parentFile?.mkdirs()

        sharedRuntime = SharedRuntime(
            baseURL = BuildConfig.API_BASE_URL,
            databasePath = databaseFile.absolutePath,
        )
    }
}
```

```swift
public struct SharedConfiguration: Sendable {
    public let baseURL: URL
    public let databasePath: String

    public init(
        baseURL: String,
        databasePath: String
    ) throws {
        guard let url = URL(string: baseURL) else {
            throw SharedRuntimeError.invalidBaseURL
        }

        self.baseURL = url
        self.databasePath = databasePath
    }
}

public struct SharedRuntime: Sendable {
    private let configuration: SharedConfiguration

    public init(
        baseURL: String,
        databasePath: String
    ) throws {
        self.configuration = try SharedConfiguration(
            baseURL: baseURL,
            databasePath: databasePath
        )
    }

    public init(configuration: SharedConfiguration) {
        self.configuration = configuration
    }

    public func makeKoma(tokenProvider: TokenProvider) async throws -> KomaClient {
        try await KomaClient.sqlite(
            database: .path(configuration.databasePath),
            schema: AppSchema.schema,
            baseURL: configuration.baseURL,
            plugins: [
                KomaBearerAuthPlugin { try await tokenProvider.token() },
                KomaRetryPlugin(maxAttempts: 2)
            ]
        )
    }
}
```

Keep Koma types inside the shared Swift module when possible. Android UI code should call app-specific bridges, such as `ProjectListUseCase.load()`, rather than constructing Koma queries directly.
