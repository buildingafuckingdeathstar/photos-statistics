// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotosStatistics",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LibraryProbe", targets: ["LibraryProbe"]),
        .executable(name: "photos-probe", targets: ["PhotosProbeCLI"])
    ],
    targets: [
        .target(name: "LibraryProbe", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "PhotosProbeCLI", dependencies: ["LibraryProbe"]),
        .testTarget(name: "LibraryProbeTests", dependencies: ["LibraryProbe"])
    ]
)
