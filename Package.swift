// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Qs",
    platforms: [
        .macOS(.v12), .iOS(.v13), .tvOS(.v13), .watchOS(.v8),
    ],
    products: [
        .library(name: "Qs", targets: ["Qs"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.1"),
        // Needed on Swift 5.10 where the Testing module is not bundled
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "Qs",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            path: "Sources/Qs",
            swiftSettings: [
                // Keep Swift 6-like checks while on 5.10
                .unsafeFlags(["-strict-concurrency=complete"], .when(configuration: .debug)),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "QsTests",
            dependencies: [
                "Qs",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/QsTests",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"], .when(configuration: .debug)),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
    ]
)
