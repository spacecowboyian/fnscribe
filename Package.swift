// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FnScribe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "fn-scribe", targets: ["FnScribe"]),
        .executable(name: "fn-scribe-menu", targets: ["FnScribeMenu"])
    ],
    targets: [
        .executableTarget(name: "FnScribe"),
        .executableTarget(name: "FnScribeMenu")
    ]
)
