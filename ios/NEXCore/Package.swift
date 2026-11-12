// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NEXCore",
    defaultLocalization: "es",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NEXCore", targets: ["NEXCore"])],
    targets: [
        .target(name: "NEXCore"),
        .testTarget(name: "NEXCoreTests", dependencies: ["NEXCore"]),
    ]
)
