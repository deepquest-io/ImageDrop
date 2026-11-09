// swift-tools-version:5.9
// ImageDrop by deepquest | https://deepquest.code511.com/blog
import PackageDescription

let package = Package(
    name: "ImageDrop",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Google's libwebp, packaged for SwiftPM (compiled from source into the app).
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "ImageDrop",
            dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")],
            path: "Sources/ImageDrop"
        )
    ]
)
