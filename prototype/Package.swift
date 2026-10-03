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
        .executableTarget(
            name: "HiveApp",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")]
        ),
    ]
)
