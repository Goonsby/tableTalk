// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TableTalkCore",
    platforms: [.iOS("18.0"), .macOS(.v13)],
    products: [.library(name: "TableTalkCore", targets: ["TableTalkCore"])],
    targets: [
        .target(name: "TableTalkCore", path: "TableTalkCore"),
        .testTarget(name: "TableTalkCoreTests", dependencies: ["TableTalkCore"], path: "TableTalkCoreTests")
    ]
)
