// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FoldLint",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "foldlint", targets: ["foldlint"]),
        .library(name: "FoldLintCore", targets: ["FoldLintCore"]),
        .plugin(name: "FoldLintPlugin", targets: ["FoldLintPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"700.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "FoldLintCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "foldlint",
            dependencies: [
                "FoldLintCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .plugin(
            name: "FoldLintPlugin",
            capability: .command(
                intent: .custom(verb: "foldlint", description: "Check the package for iPhone Duo readiness")
            ),
            dependencies: ["foldlint"]
        ),
        .testTarget(
            name: "FoldLintCoreTests",
            dependencies: ["FoldLintCore"]
        ),
    ]
)
