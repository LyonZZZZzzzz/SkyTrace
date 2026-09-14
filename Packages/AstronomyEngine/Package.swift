// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AstronomyEngine",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "AstronomyEngine", targets: ["AstronomyEngine"])
    ],
    targets: [
        .target(
            name: "CAstronomyEngine",
            path: "Sources/CAstronomyEngine",
            publicHeadersPath: "include",
            cSettings: [
                .define("ASTRONOMY_ENGINE_NO_CURRENT_TIME")
            ]
        ),
        .target(
            name: "AstronomyEngine",
            dependencies: ["CAstronomyEngine"],
            path: "Sources/AstronomyEngine"
        )
    ]
)
