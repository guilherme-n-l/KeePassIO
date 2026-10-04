// swift-tools-version: 6.1
//
// Package manifest for KeePassIOS's in-tree fork of KDBXKit. It builds the
// library and its tests only; upstream's CLI, docs plugin and fuzz targets
// are left out. See VENDORED.md for the upstream commit and local patches.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("StrictConcurrency"),
]

let package = Package(
    name: "KDBXKit",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "KDBXKit", targets: ["KDBXKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"4.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", "1.5.0"..<"2.0.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CZlib",
            path: "Sources/CZlib",
            pkgConfig: "zlib",
            providers: [
                .apt(["zlib1g-dev"]),
                .brew(["zlib"]),
            ]
        ),
        .target(
            name: "argon2",
            path: "Sources/CArgon2",
            exclude: [
                "CHANGELOG.md",
                "LICENSE",
                "UPSTREAM.md",
            ],
            sources: [
                "src/argon2.c",
                "src/core.c",
                "src/encoding.c",
                "src/ref.c",
                "src/thread.c",
                "src/blake2/blake2b.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("src"),
                .headerSearchPath("src/blake2"),
            ]
        ),
        .target(
            name: "KDBXKit",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "_CryptoExtras", package: "swift-crypto"),
                .product(name: "Logging", package: "swift-log"),
                "CZlib",
                "argon2",
            ],
            exclude: ["KDBXKit.docc"],
            resources: [
                .copy("PrivacyInfo.xcprivacy")
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "KDBXKitTests",
            dependencies: ["KDBXKit"],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
