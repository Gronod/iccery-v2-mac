// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ICCeryCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ICCeryCore", targets: ["ICCeryCore"]),
    ],
    targets: [
        .target(name: "ICCeryCore"),
    ]
)
