// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QsSwift",
    platforms: [
        .macOS(.v12), .iOS(.v13), .tvOS(.v13), .watchOS(.v8),
    ],
    products: [
        .library(name: "QsSwift", targets: ["QsSwift"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "QsSwift",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            path: "Sources/QsSwift",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"], .when(configuration: .debug)),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .testTarget(
            name: "QsSwiftTests",
            dependencies: [
                "QsSwift",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/QsSwiftTests",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"], .when(configuration: .debug)),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
    ]
)
