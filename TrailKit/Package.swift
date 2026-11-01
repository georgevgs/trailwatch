// swift-tools-version: 6.4
import PackageDescription

// GPX models, parsing, route maths and storage, shared by the iPhone and Watch apps.
// macOS is listed so `swift test` runs on the Mac without a simulator or device.
let package = Package(
    name: "TrailKit",
    platforms: [.watchOS(.v27), .iOS(.v27), .macOS(.v27)],
    products: [
        .library(name: "TrailKit", targets: ["TrailKit"])
    ],
    targets: [
        .target(name: "TrailKit"),
        .testTarget(
            name: "TrailKitTests",
            dependencies: ["TrailKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
