// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SermonSetSpeech",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "SermonSetSpeech", targets: ["SermonSetSpeech"])],
    dependencies: [
        .package(path: "../SermonSetCore"),
        .package(url: "https://github.com/FluidInference/FluidAudio", exact: "0.17.7", traits: [])
    ],
    targets: [
        .target(name: "SermonSetSpeech", dependencies: [
            "SermonSetCore", .product(name: "FluidAudio", package: "FluidAudio")
        ], resources: [.process("Resources")]),
        .testTarget(name: "SermonSetSpeechTests", dependencies: ["SermonSetSpeech"])
    ],
    swiftLanguageModes: [.v6]
)
