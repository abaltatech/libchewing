// swift-tools-version:5.9
import PackageDescription

let version = "1.0.2"
let checksum = "c36200f067dd18e06e37bcc109d60683e9d742511126d483e003b2074aad2ddb"

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
