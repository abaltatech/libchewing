// swift-tools-version:5.9
import PackageDescription

let version = "1.1.1"
let checksum = "cf8d21a46d48e88527b0702c73c8f36d3f5258463bc96045f55d23342b40a21e"

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
