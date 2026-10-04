// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "KeePassCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        // Everything the app links, as one product for the Xcode project.
        .library(
            name: "KeePassCore",
            targets: [
                "KPAppState", "KPGenerator", "KPMerge", "KPModel", "KPObservability", "KPOTP", "KPSearch",
                "KPSession", "KPKDBX",
            ]
        ),
        .library(name: "KPObservability", targets: ["KPObservability"]),
        .library(name: "KPOTP", targets: ["KPOTP"]),
        .library(name: "KPGenerator", targets: ["KPGenerator"]),
        .library(name: "KPAppState", targets: ["KPAppState"]),
        .library(name: "KPModel", targets: ["KPModel"]),
        .library(name: "KPMerge", targets: ["KPMerge"]),
        .library(name: "KPSearch", targets: ["KPSearch"]),
        .library(name: "KPSession", targets: ["KPSession"]),
        .library(name: "KPKDBX", targets: ["KPKDBX"]),
        .executable(name: "kpbench", targets: ["kpbench"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.15.1"),
        .package(path: "../../Vendor/KDBXKit"),
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
        .target(name: "KPAppState"),
        .target(name: "KPModel"),
        .testTarget(name: "KPModelTests", dependencies: ["KPModel"]),
        .target(name: "KPMerge", dependencies: ["KPModel", "KPObservability"]),
        .testTarget(name: "KPMergeTests", dependencies: ["KPMerge", "KPModel"]),
        .target(name: "KPSearch", dependencies: ["KPModel", "KPObservability"]),
        .testTarget(name: "KPSearchTests", dependencies: ["KPSearch", "KPModel"]),
        .target(
            name: "KPSession",
            dependencies: ["KPModel", "KPMerge", "KPSearch", "KPObservability", "KPAppState"]
        ),
        .testTarget(name: "KPSessionTests", dependencies: ["KPSession", "KPModel", "KPMerge"]),
        .target(
            name: "KPKDBX",
            dependencies: [
                "KPModel", "KPSession", "KPObservability",
                .product(name: "KDBXKit", package: "KDBXKit"),
            ]
        ),
        .testTarget(name: "KPKDBXTests", dependencies: ["KPKDBX", "KPModel", "KPSession", "KPOTP"]),
        .testTarget(name: "KPAppStateTests", dependencies: ["KPAppState"]),
        .testTarget(name: "KPObservabilityTests", dependencies: ["KPObservability"]),
        .testTarget(name: "KPOTPTests", dependencies: ["KPOTP"]),
        .testTarget(name: "KPGeneratorTests", dependencies: ["KPGenerator"]),
    ]
)
