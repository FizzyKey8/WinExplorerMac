// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WinExplorerMac",
    defaultLocalization: "es",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "WinExplorerMac",
            targets: ["WinExplorerMac"]
        )
    ],
    targets: [
        .executableTarget(
            name: "WinExplorerMac",
            path: "Sources/WinExplorerMac"
        )
    ]
)
