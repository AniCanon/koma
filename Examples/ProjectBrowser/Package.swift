// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "KomaProjectBrowserExample",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .executable(name: "ProjectBrowser", targets: ["ProjectBrowser"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "ProjectBrowser",
            dependencies: [
                .product(name: "Koma", package: "koma"),
                .product(name: "KomaHTTP", package: "koma"),
                .product(name: "KomaSQLite", package: "koma"),
                .product(name: "KomaTesting", package: "koma")
            ]
        ),
        .testTarget(
            name: "ProjectBrowserTests",
            dependencies: [
                "ProjectBrowser",
                .product(name: "Koma", package: "koma")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
