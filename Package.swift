// swift-tools-version: 6.0
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
        ),
        .testTarget(
            name: "QsTests",
            dependencies: ["Qs"],
            path: "Tests/QsTests",
        ),
    ]
)
