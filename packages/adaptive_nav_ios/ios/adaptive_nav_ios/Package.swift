// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "adaptive_nav_ios",
    platforms: [.iOS("13.0")],
    products: [
        .library(name: "adaptive-nav-ios", targets: ["adaptive_nav_ios"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "adaptive_nav_ios",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ]
        ),
    ]
)
