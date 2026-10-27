// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PhotosStatistics",
    platforms: [.macOS(.v14)],
    products: [.library(name: "LibraryProbe", targets: ["LibraryProbe"])],
    targets: [
        .target(name: "LibraryProbe", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "LibraryProbeTests", dependencies: ["LibraryProbe"])
    ]
)
