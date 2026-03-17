// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FileShelf",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FileShelf",
            path: "Sources/FileShelf",
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Carbon"),
            ]
        )
    ]
)
