// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NoNeedCloudCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "NoNeedCloudCore", targets: ["NoNeedCloudCore"]),
    ],
    targets: [
        .target(name: "NoNeedCloudCore"),
        .testTarget(name: "NoNeedCloudCoreTests", dependencies: ["NoNeedCloudCore"]),
    ]
)
