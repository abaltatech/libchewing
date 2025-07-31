// swift-tools-version:5.9
import PackageDescription

let version = "1.0.3"
let checksum = "9758ba861e84b98a2df54158e5678de269fda74f0530217658335f41a3b252d3"

let package = Package(
    name: "Chewing",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "Chewing",
            type: .dynamic,
            targets: ["Chewing"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "libchewing",
            url: "https://github.com/abaltatech/libchewing/releases/download/\(version)/libchewing.xcframework.zip",
            checksum: checksum
        ),
        .target(
            name: "Chewing",
            dependencies: [
                .target(name: "libchewing"),
            ],
            path: "swift/chewing-simplified/src",
            resources: [
                .process("Resources"),
            ],
            linkerSettings: [
                .linkedFramework("libchewing")
            ]
        ),
    ],
    swiftLanguageVersions: [
        .v5
    ]
)
