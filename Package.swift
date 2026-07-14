// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WhereFrom",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "WhereFrom",
            path: "Sources/WhereFrom"
        )
    ]
)
