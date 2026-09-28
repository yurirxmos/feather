// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ContextBar",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ContextBar", targets: ["ContextBar"])],
    targets: [
        .target(name: "ContextBarCore", path: "Sources/ContextBarCore"),
        .executableTarget(
            name: "ContextBar",
            dependencies: ["ContextBarCore"],
            path: "Sources/ContextBar",
            resources: [.process("Localizable.xcstrings")]
        ),
        .testTarget(
            name: "ContextBarCoreTests",
            dependencies: ["ContextBarCore"],
            path: "Tests/ContextBarCoreTests"
        ),
    ]
)
