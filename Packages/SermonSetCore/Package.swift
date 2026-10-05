// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SermonSetCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "SermonSetCore", targets: ["SermonSetCore"])],
    targets: [
        .target(name: "SermonSetCore", resources: [.process("Resources")], swiftSettings: [.enableUpcomingFeature("ExistentialAny")]),
        .testTarget(name: "SermonSetCoreTests", dependencies: ["SermonSetCore"])
    ],
    swiftLanguageModes: [.v6]
)
