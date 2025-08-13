// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QsSwiftBench",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "QsSwiftBench", targets: ["QsSwiftBench"])
    ],
    dependencies: [
        .package(name: "QsSwift", path: "..")
    ],
    targets: [
        .executableTarget(
            name: "QsSwiftBench",
            dependencies: [
                .product(name: "QsSwift", package: "QsSwift")
            ]
        )
    ]
)
