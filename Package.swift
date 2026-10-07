// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Polyglot",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        // Libraries
        .library(
            name: "PolyglotCore",
            targets: ["PolyglotCore"]
        ),
        .library(
            name: "PolyglotExtractor",
            targets: ["PolyglotExtractor"]
        ),
        .library(
            name: "PolyglotGenerator",
            targets: ["PolyglotGenerator"]
        ),
        .library(name: "PolyglotAndroidExtractor", targets: ["PolyglotAndroidExtractor"]),
        .library(name: "PolyglotAndroidGenerator", targets: ["PolyglotAndroidGenerator"]),
        .library(name: "PolyglotWebExtractor", targets: ["PolyglotWebExtractor"]),
        .library(name: "PolyglotWebGenerator", targets: ["PolyglotWebGenerator"]),
        // CLI Executable
        .executable(
            name: "polyglot",
            targets: ["polyglot"]
        ),
    ],
    dependencies: [
        // SwiftSyntax for parsing Swift source code
        .package(url: "https://github.com/apple/swift-syntax.git", from: "509.0.0"),
        // ArgumentParser for CLI command handling
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        // Core module: Shared models, protocols, API client
        .target(
            name: "PolyglotCore",
            dependencies: []
        ),
        // Extractor module: Swift code parsing and string extraction
        .target(
            name: "PolyglotExtractor",
            dependencies: [
                "PolyglotCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
        // Generator module: .strings and .stringsdict file generation
        .target(
            name: "PolyglotGenerator",
            dependencies: [
                "PolyglotCore"
            ]
        ),
        .target(
            name: "PolyglotAndroidExtractor",
            dependencies: ["PolyglotCore"]
        ),
        .target(
            name: "PolyglotAndroidGenerator",
            dependencies: ["PolyglotCore"]
        ),
        .target(
            name: "PolyglotWebExtractor",
            dependencies: ["PolyglotCore"]
        ),
        .target(
            name: "PolyglotWebGenerator",
            dependencies: ["PolyglotCore"]
        ),
        // CLI Executable: Command-line tool that orchestrates everything
        .executableTarget(
            name: "polyglot",
            dependencies: [
                "PolyglotCore",
                "PolyglotExtractor",
                "PolyglotGenerator",
                "PolyglotAndroidExtractor",
                "PolyglotAndroidGenerator",
                "PolyglotWebExtractor",
                "PolyglotWebGenerator",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // Test targets
        .testTarget(
            name: "PolyglotCoreTests",
            dependencies: ["PolyglotCore"]
        ),
        .testTarget(
            name: "PolyglotExtractorTests",
            dependencies: ["PolyglotExtractor"]
        ),
        .testTarget(
            name: "PolyglotGeneratorTests",
            dependencies: ["PolyglotGenerator"]
        ),
        .testTarget(
            name: "PolyglotAndroidExtractorTests",
            dependencies: ["PolyglotAndroidExtractor"]
        ),
        .testTarget(
            name: "PolyglotAndroidGeneratorTests",
            dependencies: ["PolyglotAndroidGenerator"]
        ),
        .testTarget(
            name: "PolyglotWebExtractorTests",
            dependencies: ["PolyglotWebExtractor"]
        ),
        .testTarget(
            name: "PolyglotWebGeneratorTests",
            dependencies: ["PolyglotWebGenerator"]
        ),
    ]
)
