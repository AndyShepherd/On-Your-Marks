// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OnYourMarks",
    platforms: [
        .macOS(.v15) // macOS 26+ — update to .v16 when SDK ships
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.4.0"),
        .package(url: "https://github.com/krzyzanowskim/STTextView.git", from: "0.9.0"),
    ],
    targets: [
        .executableTarget(
            name: "OnYourMarks",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "STTextView", package: "STTextView"),
            ],
            path: "Sources",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "OnYourMarksTests",
            dependencies: [
                "OnYourMarks",
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            path: "Tests"
        ),
    ]
)
