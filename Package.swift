// swift-tools-version:6.0
import PackageDescription

// No .xcodeproj: the machine has Command Line Tools only. Universal builds are
// two single-arch `swift build`s stitched with `lipo` (see Scripts/build-app.sh).
// Safety checks ship as `Kuori --selftest` because XCTest isn't in the CLT SDK.
let package = Package(
    name: "Kuori",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Kuori",
            path: "Sources/Kuori",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("PDFKit"),
                .linkedFramework("Vision"),
                .linkedFramework("Quartz"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
