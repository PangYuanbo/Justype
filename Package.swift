// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JustType",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JustType", targets: ["JustType"])
    ],
    targets: [
        .executableTarget(
            name: "JustType",
            path: "Sources/JustType",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Combine"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
