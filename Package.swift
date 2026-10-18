// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [.library(name: "VoiceSnippets", targets: ["VoiceSnippets"])]
var targets: [Target] = [
    .target(name: "VoiceSnippets"),
    .testTarget(name: "VoiceSnippetsTests", dependencies: ["VoiceSnippets"])
]
#if os(macOS)
products += [
    .executable(name: "fn-scribe", targets: ["FnScribe"]),
    .executable(name: "fn-scribe-menu", targets: ["FnScribeMenu"])
]
targets += [
    .executableTarget(name: "FnScribe", dependencies: ["VoiceSnippets"]),
    .executableTarget(name: "FnScribeMenu", dependencies: ["VoiceSnippets"])
]
#endif

let package = Package(
    name: "FnScribe",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
