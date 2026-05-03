// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "JustType",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "JustType", targets: ["JustType"]),
        .executable(name: "JustTypeIME", targets: ["JustTypeIME"]),
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
        ),
        .executableTarget(
            name: "JustTypeIME",
            path: "Sources/JustTypeIME",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("InputMethodKit"),
            ]
        ),
    ]
)
