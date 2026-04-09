// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "APRelay",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(url: "https://github.com/vapor/fluent.git", from: "4.9.0"),
        .package(url: "https://github.com/vapor/fluent-sqlite-driver.git", from: "4.6.0"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.9.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "5.0.0"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0"),
        .package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "APRelayCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "Collections", package: "swift-collections"),
            ]
        ),
        .executableTarget(
            name: "APRelay",
            dependencies: [
                "APRelayCore",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "Fluent", package: "fluent"),
                .product(name: "FluentSQLiteDriver", package: "fluent-sqlite-driver"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "Prometheus", package: "swift-prometheus"),
            ]
        ),
        .testTarget(
            name: "APRelayCoreTests",
            dependencies: ["APRelayCore"]
        ),
        .testTarget(
            name: "APRelayTests",
            dependencies: [
                "APRelay",
                .product(name: "VaporTesting", package: "vapor"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
