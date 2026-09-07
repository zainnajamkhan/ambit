// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ambit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AmbitCore", targets: ["AmbitCore"]),
        .library(name: "AmbitCapture", targets: ["AmbitCapture"]),
        .executable(name: "ambit-spike-ax", targets: ["ambit-spike-ax"]),
    ],
    targets: [
        // Pure logic. No system frameworks, no I/O, fully testable.
        // Strict concurrency is on here because everything is a value type.
        .target(
            name: "AmbitCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // The system edge: Accessibility, NSWorkspace, CGEventSource.
        // Swift 5 language mode: AXObserver hands back bare C function pointers
        // that cannot capture context, and the run loop plumbing around them
        // does not model cleanly under strict concurrency. Revisit once the
        // capture engine has settled.
        .target(
            name: "AmbitCapture",
            dependencies: ["AmbitCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .executableTarget(
            name: "ambit-spike-ax",
            dependencies: ["AmbitCapture", "AmbitCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .testTarget(
            name: "AmbitCoreTests",
            dependencies: ["AmbitCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
