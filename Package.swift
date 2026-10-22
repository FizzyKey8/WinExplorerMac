// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Win11ExplorerMac",
    defaultLocalization: "es",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Win11ExplorerMac",
            targets: ["Win11ExplorerMac"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Win11ExplorerMac",
            path: "Sources/Win11ExplorerMac"
        )
    ]
)
