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
        .library(name: "KPOTP", targets: ["KPOTP"]),
        .library(name: "KPGenerator", targets: ["KPGenerator"]),
        .executable(name: "kpbench", targets: ["kpbench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "4.5.2"),
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
        .target(name: "KPOTP", dependencies: [.product(name: "Crypto", package: "swift-crypto")]),
        .target(name: "KPGenerator", resources: [.copy("Resources/eff_large_wordlist.txt")]),
        .testTarget(name: "KPObservabilityTests", dependencies: ["KPObservability"]),
        .testTarget(name: "KPOTPTests", dependencies: ["KPOTP"]),
        .testTarget(name: "KPGeneratorTests", dependencies: ["KPGenerator"]),
    ]
)
