// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QsSwift",
    platforms: [
        .macOS(.v12), .iOS(.v13), .tvOS(.v13), .watchOS(.v8),
    ],
    products: [
        .library(name: "QsSwift", targets: ["QsSwift"]),
        .library(name: "QsObjC", targets: ["QsObjC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.1"),
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
            path: "Sources/QsSwift"
        ),
        .target(
            name: "QsObjC",
            dependencies: ["QsSwift"],
            path: "Sources/QsObjC",
            swiftSettings: [
                .define("QS_OBJC_BRIDGE", .when(platforms: [.macOS, .iOS, .tvOS, .watchOS]))
            ]
        ),
        .testTarget(
            name: "QsSwiftTests",
            dependencies: ["QsSwift"],
            path: "Tests/QsSwiftTests"
        ),
        .testTarget(
            name: "QsObjCTests",
            dependencies: [
                "QsSwift",
                "QsObjC",
            ],
            path: "Tests/QsObjCTests"
        ),
    ]
)
