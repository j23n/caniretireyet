// swift-tools-version: 6.2
import PackageDescription

/// Library modules, in dependency order. Each one is exported as a product so
/// the app (App/project.yml) can link it, and gets a test target named
/// `<Module>Tests` that also depends on `TestSupport`.
let libraries: [(name: String, dependencies: [Target.Dependency])] = [
    ("Model", []),
    ("Tracker", ["Model"]),
    ("Storage", ["Model"]),
    ("Importer", ["Model"]),
    ("Prices", ["Model"]),
    ("Planner", ["Model", "Tracker"]),
    ("CloudSync", ["Model", "Storage"]),
    // What the widgets show: built from the library with Tracker's net
    // worth, change and breakdown, read by the widget extension.
    ("Glance", ["Model", "Tracker"]),
]

/// Test targets that ship resources, e.g. sample files.
let testResources: [String: [Resource]] = [
    "ImporterTests": [.copy("Samples")],
]

/// Test targets that need more than their module and `TestSupport`. The
/// importer's tests check the holdings, average cost and cash of imported
/// trades with Tracker's `TradeLedger`; `Importer` itself doesn't use it.
let testDependencies: [String: [Target.Dependency]] = [
    "ImporterTests": ["Tracker"],
]

let package = Package(
    name: "CanIRetireYetKit",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: libraries.map { .library(name: $0.name, targets: [$0.name]) } + [
        .executable(name: "retire", targets: ["retire"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: libraries.map { library in
        .target(name: library.name, dependencies: library.dependencies)
    } + libraries.map { library in
        .testTarget(
            name: "\(library.name)Tests",
            dependencies: [.target(name: library.name), "TestSupport"]
                + (testDependencies["\(library.name)Tests"] ?? []),
            resources: testResources["\(library.name)Tests"]
        )
    } + [
        // Test-only helpers and the made-up example library. Not a product.
        .target(
            name: "TestSupport",
            dependencies: ["Model"],
            resources: [.copy("Resources/ExampleLibrary")]
        ),
        // The `retire` command-line tool: its commands live in `RetireCLI`,
        // a library so they can be tested, and the executable only starts it.
        // It uses Tracker for net worth, breakdowns and the change split.
        .target(
            name: "RetireCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Model", "Tracker", "Storage", "Importer", "Planner", "Prices",
            ]
        ),
        .executableTarget(
            name: "retire",
            dependencies: ["RetireCLI"]
        ),
        .testTarget(
            name: "RetireCLITests",
            dependencies: ["RetireCLI", "TestSupport", "Model", "Storage", "Prices", "Planner", "Tracker"],
            resources: [.copy("Samples")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
