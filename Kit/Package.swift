// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MlisbKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MlisbKit", targets: ["MlisbKit"])],
    dependencies: [.package(path: "../Vendor/MarkdownEngine")],
    targets: [
        .target(name: "MlisbKit",
                dependencies: [.product(name: "MarkdownEngine", package: "MarkdownEngine")],
                resources: [.copy("Resources/render")]),
        .testTarget(name: "MlisbKitTests", dependencies: ["MlisbKit"]),
    ]
)
