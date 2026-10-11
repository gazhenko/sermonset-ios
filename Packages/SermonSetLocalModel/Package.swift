// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SermonSetLocalModel",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [.library(name: "SermonSetLocalModel", targets: ["SermonSetLocalModel"])],
    dependencies: [
        .package(path: "../SermonSetCore"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", exact: "2.31.3")
    ],
    targets: [
        .target(name: "SermonSetLocalModel", dependencies: [
            "SermonSetCore",
            .product(name: "MLXLLM", package: "mlx-swift-lm"),
            .product(name: "MLXLMCommon", package: "mlx-swift-lm")
        ]),
        .testTarget(name: "SermonSetLocalModelTests", dependencies: ["SermonSetLocalModel"])
    ],
    swiftLanguageModes: [.v6]
)
