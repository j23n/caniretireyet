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
    ("TaxKit", []),
    ("TaxGeneric", ["TaxKit"]),
    ("TaxItaly", ["TaxKit"]),
    ("Planner", ["Model", "Tracker", "TaxKit"]),
    ("CloudSync", ["Model", "Storage"]),
]

/// Targets that ship resources.
let resources: [String: [Resource]] = [
    "TaxItaly": [.process("Resources")],
]

/// Test targets that ship resources, e.g. sample files.
let testResources: [String: [Resource]] = [
    "ImporterTests": [.copy("Samples")],
    "TaxItalyTests": [.copy("cases")],
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
        .target(
            name: library.name,
            dependencies: library.dependencies,
            resources: resources[library.name]
        )
    } + libraries.map { library in
        .testTarget(
            name: "\(library.name)Tests",
            dependencies: [.target(name: library.name), "TestSupport"],
            resources: testResources["\(library.name)Tests"]
        )
    } + [
        // Test-only helpers and the made-up example library. Not a product.
        .target(
            name: "TestSupport",
            dependencies: ["Model"],
            resources: [.copy("Resources/ExampleLibrary")]
        ),
        .executableTarget(
            name: "retire",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Storage", "Importer", "Planner", "Prices",
                "TaxKit", "TaxGeneric", "TaxItaly",
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
