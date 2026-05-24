// swift-tools-version: 6.3

import CompilerPluginSupport
import Foundation
import PackageDescription

let enableBenchmarks = ProcessInfo.processInfo.environment["KOMA_ENABLE_BENCHMARKS"] == "1"

let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.0" ..< "604.0.0")
] + (enableBenchmarks ? [
    .package(url: "https://github.com/Alamofire/Alamofire.git", exact: "5.12.0"),
    .package(url: "https://github.com/Moya/Moya.git", exact: "15.0.3"),
    .package(url: "https://github.com/apollographql/apollo-ios.git", exact: "2.1.2"),
    .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0"),
    .package(
        url: "https://github.com/stephencelis/SQLite.swift.git",
        exact: "0.16.0",
        traits: [.trait(name: "SQLiteSwiftCSQLite")]
    ),
    .package(url: "https://github.com/ordo-one/benchmark", exact: "1.33.0")
] : [])

let benchmarkTargets: [Target] = enableBenchmarks ? [
    .target(
        name: "KomaBenchmarkSupport",
        dependencies: [
            "Koma",
            "KomaMacros"
        ],
        path: "Benchmarks/KomaBenchmarkSupport"
    ),
    .target(
        name: "KomaBenchmarkSQLiteSupport",
        dependencies: [
            "CKomaSQLite",
            "KomaBenchmarkSupport"
        ],
        path: "Benchmarks/KomaBenchmarkSQLiteSupport"
    ),
    .target(
        name: "KomaAndroidBenchmarkCore",
        path: "Benchmarks/KomaAndroidBenchmarkCore"
    ),
    .executableTarget(
        name: "KomaBenchmarks",
        dependencies: [
            "Koma",
            "KomaBenchmarkSupport",
            "KomaBenchmarkSQLiteSupport",
            "KomaHTTP",
            "KomaMacros",
            "KomaSQLite",
            "KomaTesting",
            .product(name: "Alamofire", package: "Alamofire"),
            .product(name: "Apollo", package: "apollo-ios"),
            .product(name: "ApolloAPI", package: "apollo-ios"),
            .product(name: "Benchmark", package: "benchmark"),
            .product(name: "GRDB", package: "GRDB.swift"),
            .product(name: "Moya", package: "Moya")
        ],
        path: "Benchmarks/KomaBenchmarks",
        plugins: [
            .plugin(name: "BenchmarkPlugin", package: "benchmark")
        ]
    ),
    .executableTarget(
        name: "KomaAndroidBenchmarks",
        dependencies: [
            "Koma",
            "KomaAndroidBenchmarkCore",
            "KomaBenchmarkSupport",
            "KomaBenchmarkSQLiteSupport",
            "KomaSQLite",
            .product(name: "GRDB", package: "GRDB.swift")
        ],
        path: "Benchmarks/KomaAndroidBenchmarks"
    ),
    .executableTarget(
        name: "KomaAndroidSQLiteSwiftBenchmarks",
        dependencies: [
            "KomaAndroidBenchmarkCore",
            "KomaBenchmarkSupport",
            .product(name: "SQLite", package: "SQLite.swift")
        ],
        path: "Benchmarks/KomaAndroidSQLiteSwiftBenchmarks"
    )
] : []

let package = Package(
    name: "Koma",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "Koma", targets: ["Koma"]),
        .library(name: "KomaMacros", targets: ["KomaMacros"]),
        .library(name: "KomaSQLite", targets: ["KomaSQLite"]),
        .library(name: "KomaHTTP", targets: ["KomaHTTP"]),
        .library(name: "KomaTesting", targets: ["KomaTesting"])
    ],
    dependencies: dependencies,
    targets: [
        .target(
            name: "CKomaSQLite",
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_THREADSAFE", to: "1"),
                .define("SQLITE_OMIT_LOAD_EXTENSION"),
                .define("SQLITE_ENABLE_JSON1"),
                .define("SQLITE_ENABLE_FTS5"),
                .define("SQLITE_ENABLE_SNAPSHOT")
            ]
        ),
        .target(
            name: "Koma"
        ),
        .target(
            name: "KomaMacros",
            dependencies: ["Koma", "KomaMacroPlugin"]
        ),
        .target(
            name: "KomaSQLite",
            dependencies: ["CKomaSQLite", "Koma"]
        ),
        .target(
            name: "KomaHTTP",
            dependencies: ["Koma"]
        ),
        .target(
            name: "KomaTesting",
            dependencies: ["Koma"]
        ),
        .macro(
            name: "KomaMacroPlugin",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "KomaTests",
            dependencies: [
                "Koma",
                "KomaHTTP",
                "KomaMacros",
                "KomaMacroPlugin",
                "KomaSQLite",
                "KomaTesting",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        )
    ] + benchmarkTargets,
    swiftLanguageModes: [.v6]
)
