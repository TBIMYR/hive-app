// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HiveApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 1.21 announces breaking changes, so stay on 1.20.x
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", .upToNextMinor(from: "1.20.0")),
        // Handover display: Markdown with tables, code blocks, quotes
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", .upToNextMinor(from: "2.4.1")),
    ],
    targets: [
        // Reads registry, handover and conversation transcripts (replaces hive/lib/*.js)
        .target(name: "HiveCore"),
        .executableTarget(
            name: "HiveApp",
            dependencies: [
                "HiveCore",
                "VoiceKit",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),
        // Prints the state like GET /api/state, for comparison with the Node server
        .executableTarget(name: "hive-state", dependencies: ["HiveCore"]),
        // Talking to Hive: the logic without audio (sentences, markers, confirmation gate, spoken names)
        .target(name: "VoiceKit", dependencies: ["HiveCore"]),
        .testTarget(name: "HiveCoreTests", dependencies: ["HiveCore"], resources: [.copy("Fixtures")]),
        .testTarget(name: "VoiceKitTests", dependencies: ["VoiceKit", "HiveCore"]),
    ]
)
