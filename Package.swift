// swift-tools-version:5.9
import PackageDescription

let version = "1.1.3"
let checksum = "9be38db45e6113cee2f4d4a83186538f69918df7b9f9440162a1153d9969f686"

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
