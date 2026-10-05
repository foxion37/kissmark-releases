// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KissmarkMCP",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "KissmarkConnections", targets: ["KissmarkConnections"])],
    targets: [
        .target(name: "KissmarkConnections", path: "Shared"),
        .executableTarget(
            name: "kissmark-mcp",
            dependencies: ["KissmarkConnections"],
            path: "Sources",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "ClientSetupTests",
            dependencies: ["kissmark-mcp", "KissmarkConnections"],
            path: "Tests/ClientSetupTests"
        )
    ]
)
