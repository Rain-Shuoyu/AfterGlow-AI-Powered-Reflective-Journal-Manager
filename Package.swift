// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "ShiGuang",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "ShiGuang", targets: ["ShiGuang"])
    ],
    targets: [
        .executableTarget(
            name: "ShiGuang",
            path: "Sources/ShiGuang",
            resources: []
        )
    ]
)
