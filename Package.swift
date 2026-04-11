// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "APRelay",
    platforms: [
        .macOS(.v14),
    ],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.99.0"),
        .package(url: "https://github.com/vapor/queues-redis-driver.git", from: "1.1.0"),
        .package(url: "https://github.com/vapor/queues.git", from: "1.12.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0" ..< "5.0.0"),
        .package(url: "https://github.com/swift-server/swift-prometheus.git", from: "2.0.0"),
        .package(url: "https://github.com/vapor/leaf.git", from: "4.4.0"),
    ],
    targets: [
        .target(
            name: "APRelayCore",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .executableTarget(
            name: "APRelay",
            dependencies: [
                "APRelayCore",
                .product(name: "Vapor", package: "vapor"),
                .product(name: "QueuesRedisDriver", package: "queues-redis-driver"),
                .product(name: "Prometheus", package: "swift-prometheus"),
                .product(name: "Leaf", package: "leaf"),
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
                .product(name: "XCTQueues", package: "queues"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
