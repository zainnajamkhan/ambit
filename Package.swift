// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Ambit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AmbitCore", targets: ["AmbitCore"]),
        .library(name: "AmbitStore", targets: ["AmbitStore"]),
        .library(name: "AmbitCapture", targets: ["AmbitCapture"]),
        .executable(name: "Ambit", targets: ["AmbitApp"]),
        .executable(name: "ambit-spike-ax", targets: ["ambit-spike-ax"]),
    ],
    dependencies: [
        // SQLite, because this is a time series of many small rows with a lot of range
        // queries over it. A pure Swift wrapper with no networking in it, which matters
        // for an app whose whole claim is that it cannot reach the outside world.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // Pure logic. No system frameworks, no I/O, fully testable.
        // Strict concurrency is on here because everything is a value type.
        .target(
            name: "AmbitCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // Persistence. Append only: the log is written and read, never edited.
        .target(
            name: "AmbitStore",
            dependencies: ["AmbitCore", .product(name: "GRDB", package: "GRDB.swift")],
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

        // The app itself: menu bar, day timeline, week summary.
        .executableTarget(
            name: "AmbitApp",
            dependencies: ["AmbitCore", "AmbitCapture", "AmbitStore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .executableTarget(
            name: "ambit-spike-ax",
            dependencies: ["AmbitCapture", "AmbitCore", "AmbitStore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .testTarget(
            name: "AmbitCoreTests",
            dependencies: ["AmbitCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),

        // GRDB is a direct dependency here so the tests can write a deliberately
        // malformed row and prove the store degrades instead of refusing to open.
        .testTarget(
            name: "AmbitStoreTests",
            dependencies: [
                "AmbitStore",
                "AmbitCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
