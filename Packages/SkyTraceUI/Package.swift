// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SkyTraceUI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SkyTraceUI", targets: ["SkyTraceUI"])
    ],
    dependencies: [
        .package(path: "../SkyTraceCore")
    ],
    targets: [
        .target(
            name: "SkyTraceUI",
            dependencies: [
                .product(name: "SkyTraceCore", package: "SkyTraceCore")
            ],
            path: "Sources/SkyTraceUI",
            swiftSettings: [
                .enableUpcomingFeature("ExistentialAny")
            ]
        )
    ]
)
