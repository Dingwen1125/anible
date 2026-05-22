// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "AnibleDesktopPet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AniblePet", targets: ["AniblePet"])
    ],
    targets: [
        .executableTarget(
            name: "AniblePet",
            path: "Sources/AniblePet"
        )
    ]
)
