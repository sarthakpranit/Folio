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
        .package(url: "https://github.com/SwiftyJSON/SwiftyJSON.git", from: "5.0.1")
    ],
    targets: [
        .target(
            name: "FolioCore",
            dependencies: [
                .product(name: "Swifter", package: "swifter"),
                .product(name: "SwiftyJSON", package: "SwiftyJSON")
            ],
            swiftSettings: [
                // M1 (ADR-0004): complete concurrency checking as WARNINGS while
                // still in Swift 5 language mode. The M1 tickets burn these down;
                // the language-mode flip to Swift 6 is gated on zero warnings.
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "FolioCoreTests",
            dependencies: ["FolioCore"]
        )
    ]
)
