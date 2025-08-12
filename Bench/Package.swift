// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "QsBench",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "QsBench", targets: ["QsBench"])
    ],
    dependencies: [
        .package(name: "Qs", path: "..")
    ],
    targets: [
        .executableTarget(
            name: "QsBench",
            dependencies: [
                .product(name: "Qs", package: "Qs")
            ]
        )
    ]
)
