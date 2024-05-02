// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TextToStructure",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "TextToStructure",
            targets: ["TextToStructure", "LlamaHelpers"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ggerganov/llama.cpp.git", revision: "b8109bc0139f15a5b321909f47510b89dca47ffc"),
        ],
    targets: [
        .target(
            name: "LlamaHelpers", dependencies: [.product(name: "llama", package: "llama.cpp")], path: "Sources/LlamaHelpers"
        ),
        .target(
            name: "TextToStructure", dependencies: [.product(name: "llama", package: "llama.cpp"), "LlamaHelpers"], path: "Sources/TextToStructure", swiftSettings: [.interoperabilityMode(.Cxx)]),
        .testTarget(
            name: "TextToStructureTests",
            dependencies: ["TextToStructure"]),
    ],
    cxxLanguageStandard: .cxx11
)
