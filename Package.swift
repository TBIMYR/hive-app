// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HiveApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        // 1.21 kündigt Breaking Changes an, darum auf 1.20.x festhalten
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", .upToNextMinor(from: "1.20.0")),
    ],
    targets: [
        // Liest Register, Handover und Gesprächsprotokolle (ersetzt hive/lib/*.js)
        .target(name: "HiveCore"),
        .executableTarget(
            name: "HiveApp",
            dependencies: ["HiveCore", .product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
        // Gibt den Zustand wie GET /api/state aus, für den Vergleich mit dem Node-Server
        .executableTarget(name: "hive-state", dependencies: ["HiveCore"]),
        .testTarget(name: "HiveCoreTests", dependencies: ["HiveCore"], resources: [.copy("Fixtures")]),
    ]
)
