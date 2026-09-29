// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Feather",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Feather", targets: ["Feather"])],
    targets: [
        .target(name: "FeatherCore", path: "Sources/FeatherCore"),
        .executableTarget(
            name: "Feather",
            dependencies: ["FeatherCore"],
            path: "Sources/Feather",
            resources: [.process("Localizable.xcstrings")]
        ),
        .testTarget(
            name: "FeatherCoreTests",
            dependencies: ["FeatherCore"],
            path: "Tests/FeatherCoreTests"
        ),
    ]
)
