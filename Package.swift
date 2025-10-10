// swift-tools-version:5.9
import PackageDescription

let version = "1.1.2"
let checksum = "4ff58ea2ab26e48bbae2f6f3b18fd48340af024f4a34e194da5aad71c2a57be5"

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
