// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "ICCeryCore",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "ICCeryCore", targets: ["ICCeryCore"]),
    ],
    targets: [
        .target(name: "ICCeryCore"),
    ]
)
