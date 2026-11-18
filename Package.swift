// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacLaunch",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacLaunch", targets: ["MacLaunch"])],
    targets: [
        .executableTarget(name: "MacLaunch"),
        .testTarget(name: "MacLaunchTests", dependencies: ["MacLaunch"])
    ]
)
