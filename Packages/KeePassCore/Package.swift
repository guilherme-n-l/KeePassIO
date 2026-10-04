// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeePassCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "KPObservability", targets: ["KPObservability"]),
        .executable(name: "kpbench", targets: ["kpbench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2")
    ],
    targets: [
        .target(name: "KPObservability"),
        .executableTarget(
            name: "kpbench",
            dependencies: [
                "KPObservability",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "KPObservabilityTests", dependencies: ["KPObservability"]),
    ]
)
