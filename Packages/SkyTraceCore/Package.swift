// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SkyTraceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SkyTraceCore", targets: ["SkyTraceCore"])
    ],
    dependencies: [
        .package(path: "../AstronomyEngine")
    ],
    targets: [
        .target(
            name: "SkyTraceCore",
            dependencies: [
                .product(name: "AstronomyEngine", package: "AstronomyEngine")
            ],
            path: "Sources/SkyTraceCore",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        ),
        .testTarget(
            name: "SkyTraceCoreTests",
            dependencies: ["SkyTraceCore"],
            path: "Tests/SkyTraceCoreTests"
        )
    ]
)
