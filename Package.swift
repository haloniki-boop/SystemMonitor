// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SystemMonitor",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SystemMonitor", targets: ["SystemMonitor"])
    ],
    targets: [
        .executableTarget(name: "SystemMonitor"),
        .testTarget(name: "SystemMonitorTests", dependencies: ["SystemMonitor"])
    ]
)
