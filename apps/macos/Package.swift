// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NoNeedCloud",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "NoNeedCloud"),
        .testTarget(
            name: "NoNeedCloudTests",
            dependencies: ["NoNeedCloud"]
        ),
    ]
)
