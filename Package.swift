// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mug-uninstaller",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MugUninstallerKit", targets: ["MugUninstallerKit"]),
        .executable(name: "mug-uninstaller-cli", targets: ["mug-uninstaller-cli"]),
        .executable(name: "mug-uninstaller", targets: ["mug-uninstaller"]),
    ],
    targets: [
        .target(name: "MugUninstallerKit"),
        .executableTarget(name: "mug-uninstaller-cli", dependencies: ["MugUninstallerKit"]),
        .executableTarget(name: "mug-uninstaller", dependencies: ["MugUninstallerKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
