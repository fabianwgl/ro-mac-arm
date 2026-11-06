// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ROProbe",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "ro-probe", targets: ["ro-probe"]),
    ],
    dependencies: [
        .package(path: "../../Packages/BinaryIO"),
        .package(path: "../../Packages/RagnarokConstants"),
        .package(path: "../../Packages/RagnarokCore"),
        .package(path: "../../Packages/RagnarokGame"),
        .package(path: "../../Packages/RagnarokGRF"),
        .package(path: "../../Packages/RagnarokModels"),
        .package(path: "../../Packages/RagnarokNetwork"),
        .package(path: "../../Packages/RagnarokPackets"),
        .package(path: "../../Packages/RagnarokResources"),
    ],
    targets: [
        .executableTarget(
            name: "ro-probe",
            dependencies: [
                "BinaryIO",
                "RagnarokConstants",
                "RagnarokCore",
                "RagnarokGame",
                "RagnarokGRF",
                "RagnarokModels",
                "RagnarokNetwork",
                "RagnarokPackets",
                "RagnarokResources",
            ]
        ),
    ]
)
