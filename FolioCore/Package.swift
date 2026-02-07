// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FolioCore",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(name: "FolioCore", targets: ["FolioCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/httpswift/swifter.git", from: "1.5.0"),
        .package(url: "https://github.com/onevcat/Kingfisher.git", from: "7.11.0"),
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.1")
    ],
    targets: [
        .target(
            name: "FolioCore",
            dependencies: [
                .product(name: "Swifter", package: "swifter"),
                .product(name: "Kingfisher", package: "Kingfisher"),
                .product(name: "SwiftyJSON", package: "SwiftyJSON")
            ]
        ),
        .testTarget(
            name: "FolioCoreTests",
            dependencies: ["FolioCore"]
        )
    ]
)
