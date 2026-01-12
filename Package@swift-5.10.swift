// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

var deps: [Package.Dependency] = [
    .package(url: "https://github.com/apple/swift-algorithms.git", from: "1.2.1"),
    .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.1"),
    .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.1.0"),
    .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0"),
]
var targetDeps: [Target.Dependency] = [
    .product(name: "Algorithms", package: "swift-algorithms"),
    .product(name: "OrderedCollections", package: "swift-collections"),
]
#if os(Linux)
    deps.append(.package(url: "https://github.com/reers/ReerKit.git", from: "1.2.2"))
    targetDeps.append(.product(name: "ReerKit", package: "ReerKit"))
#endif

let package = Package(
    name: "QsSwift",
    platforms: [
        .macOS(.v12), .iOS(.v13), .tvOS(.v13), .watchOS(.v8),
    ],
    products: [
        .library(name: "QsSwift", targets: ["QsSwift"]),
        .library(name: "QsObjC", targets: ["QsObjC"]),
    ],
    dependencies: deps,
    targets: [
        .target(
            name: "QsSwift",
            dependencies: targetDeps,
            path: "Sources/QsSwift",
            swiftSettings: [
                .unsafeFlags(["-strict-concurrency=complete"], .when(configuration: .debug)),
                .unsafeFlags(["-enable-actor-data-race-checks"], .when(configuration: .debug)),
            ]
        ),
        .target(
            name: "QsObjC",
            dependencies: ["QsSwift"],
            path: "Sources/QsObjC",
            exclude: ["README.md"],
            swiftSettings: [
                .define("QS_OBJC_BRIDGE", .when(platforms: [.macOS, .iOS, .tvOS, .watchOS]))
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
        .testTarget(
            name: "QsObjCTests",
            dependencies: [
                "QsSwift",
                "QsObjC",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/QsObjCTests"
        ),
        .executableTarget(
            name: "QsSwiftComparison",
            dependencies: ["QsSwift"],
            path: "Tools/QsSwiftComparison",
            exclude: [
                "js/node_modules",
                "js/package.json",
                "js/package-lock.json",
                "js/qs.js",
                "compare_outputs.sh",
            ],
            resources: [
                .copy("js/test_cases.json")
            ]
        ),
    ]
)
