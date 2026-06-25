// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SoftFocus",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic, no UI — so it can be unit-tested without a running app.
        .target(name: "SoftFocusCore"),
        // The actual Mac app (AppKit/SwiftUI glue).
        .executableTarget(
            name: "SoftFocus",
            dependencies: ["SoftFocusCore"],
            exclude: ["GoogleConfig.swift.example"]
        ),
        .testTarget(
            name: "SoftFocusCoreTests",
            dependencies: ["SoftFocusCore"]
        ),
    ]
)
