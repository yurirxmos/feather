// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Feather",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Feather", targets: ["Feather"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "FeatherCore", path: "Sources/FeatherCore"),
        .executableTarget(
            name: "Feather",
            dependencies: ["FeatherCore", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Feather",
            resources: [.process("Localizable.xcstrings"), .copy("ProviderLogos")]
        ),
        .testTarget(
            name: "FeatherCoreTests",
            dependencies: ["FeatherCore"],
            path: "Tests/FeatherCoreTests"
        ),
    ]
)
