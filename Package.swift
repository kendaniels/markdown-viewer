// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkdownViewer",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(
            name: "MarkdownViewer",
            targets: ["MarkdownViewer"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "MarkdownViewer",
            path: "Sources"
        ),
        .testTarget(
            name: "MarkdownViewerTests",
            dependencies: ["MarkdownViewer"],
            path: "Tests"
        ),
    ]
)
