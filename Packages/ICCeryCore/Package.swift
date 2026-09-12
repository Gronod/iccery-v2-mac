// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "ICCeryCore",
    platforms: [.macOS(.v12)],
    products: [
        // Static so app + test bundles each link ICCeryCore directly —
        // a dynamic package product framework is not embedded in the
        // .app and dyld kills the app at launch on macOS 12 (#117).
        .library(name: "ICCeryCore", type: .static, targets: ["ICCeryCore"]),
    ],
    targets: [
        .target(name: "ICCeryCore"),
    ]
)
