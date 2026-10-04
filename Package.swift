// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HiveApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 1.21 kündigt Breaking Changes an, darum auf 1.20.x festhalten
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", .upToNextMinor(from: "1.20.0")),
        // Handover-Anzeige: Markdown mit Tabellen, Code-Blöcken, Zitaten
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", .upToNextMinor(from: "2.4.1")),
    ],
    targets: [
        // Liest Register, Handover und Gesprächsprotokolle (ersetzt hive/lib/*.js)
        .target(name: "HiveCore"),
        .executableTarget(
            name: "HiveApp",
            dependencies: [
                "HiveCore",
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ]
        ),
        // Gibt den Zustand wie GET /api/state aus, für den Vergleich mit dem Node-Server
        .executableTarget(name: "hive-state", dependencies: ["HiveCore"]),
        .testTarget(name: "HiveCoreTests", dependencies: ["HiveCore"], resources: [.copy("Fixtures")]),
    ]
)
