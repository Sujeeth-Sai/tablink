// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TabLink", platforms: [.macOS(.v13)], products: [
    .executable(name: "TabLink", targets: ["TabLink"]),
    .executable(name: "TabLinkWatchdog", targets: ["TabLinkWatchdog"])
], targets: [
    .target(name: "TabLinkCore"),
    .executableTarget(name: "TabLink", dependencies: ["TabLinkCore"]),
    .executableTarget(name: "TabLinkWatchdog"),
    .testTarget(name: "TabLinkCoreTests", dependencies: ["TabLinkCore"])
])
