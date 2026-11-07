// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AgentPackageManagerDesktop",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AgentPackageManagerDesktop",
            path: "Sources"
        ),
        .testTarget(
            name: "APMTests",
            dependencies: ["AgentPackageManagerDesktop"],
            path: "Tests"
        )
    ]
)
