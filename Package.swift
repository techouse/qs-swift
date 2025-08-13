// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Qs",
    platforms: [
        .macOS(.v12), .iOS(.v13), .tvOS(.v13), .watchOS(.v8),
    ],
    products: [
        .library(name: "Qs", targets: ["Qs"]),
        .library(name: "QsObjC", targets: ["QsObjC"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.1"),
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"),
    ],
    targets: [
        .target(
            name: "Qs",
            dependencies: [
                .product(name: "Algorithms", package: "swift-algorithms"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "DequeModule", package: "swift-collections"),
            ],
            path: "Sources/Qs"
        ),
        .target(
            name: "QsObjC",
            dependencies: ["Qs"],
            path: "Sources/QsObjC"
        ),
        .testTarget(
            name: "QsTests",
            dependencies: ["Qs"],
            path: "Tests/QsTests",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-adhoc_codesign"], .when(platforms: [.macOS]))
            ]
        ),
        .testTarget(
            name: "QsObjCTests",
            dependencies: [
                "Qs",
                "QsObjC",
            ],
            path: "Tests/QsObjCTests",
            linkerSettings: [
                // Make the test binary ad-hoc signed at link time (macOS only)
                .unsafeFlags(["-Xlinker", "-adhoc_codesign"], .when(platforms: [.macOS]))
            ]
        ),
    ]
)
