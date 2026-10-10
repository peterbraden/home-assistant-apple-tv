// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HomeAssistantKit",
    platforms: [.tvOS(.v17), .iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HomeAssistantKit", targets: ["HomeAssistantKit"]),
    ],
    targets: [
        .target(name: "HomeAssistantKit"),
        .testTarget(name: "HomeAssistantKitTests", dependencies: ["HomeAssistantKit"]),
    ]
)
