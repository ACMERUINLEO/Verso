// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VersoCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "VersoDomain", targets: ["VersoDomain"]),
        .library(name: "VersoApplication", targets: ["VersoApplication"]),
        .library(name: "VersoSyncProtocol", targets: ["VersoSyncProtocol"]),
        .library(name: "VersoPersistence", targets: ["VersoPersistence"]),
        .library(name: "VersoFileSystem", targets: ["VersoFileSystem"]),
        .library(name: "VersoObservability", targets: ["VersoObservability"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            from: "7.11.1"
        )
    ],
    targets: [
        .target(name: "VersoDomain"),
        .target(
            name: "VersoSyncProtocol",
            dependencies: ["VersoDomain"]
        ),
        .target(
            name: "VersoApplication",
            dependencies: ["VersoDomain", "VersoSyncProtocol"]
        ),
        .target(
            name: "VersoPersistence",
            dependencies: [
                "VersoDomain",
                "VersoApplication",
                "VersoSyncProtocol",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .target(
            name: "VersoFileSystem",
            dependencies: ["VersoApplication"]
        ),
        .target(
            name: "VersoObservability",
            dependencies: ["VersoApplication"]
        ),
        .testTarget(
            name: "VersoApplicationTests",
            dependencies: ["VersoApplication"]
        ),
        .testTarget(
            name: "VersoSyncProtocolTests",
            dependencies: ["VersoSyncProtocol"]
        ),
        .testTarget(
            name: "VersoPersistenceTests",
            dependencies: [
                "VersoPersistence",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            resources: [.process("Fixtures")]
        ),
        .testTarget(
            name: "VersoFileSystemTests",
            dependencies: ["VersoFileSystem", "VersoApplication"]
        ),
        .testTarget(
            name: "VersoObservabilityTests",
            dependencies: ["VersoObservability", "VersoApplication"]
        )
    ],
    swiftLanguageModes: [.v6]
)
