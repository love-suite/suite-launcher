// swift-tools-version:5.9
import PackageDescription

// Launcher: the grid of apps in place of Launchpad, as an app of its own. Its logic stays UI-free in
// LauncherCore; Bar opens it through SuiteCore's LauncherApp and LauncherMessage.
let suiteCore = Target.Dependency.product(name: "SuiteCore", package: "suite-core")

let package = Package(
    name: "Launcher",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LauncherCore", targets: ["LauncherCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/paul-amour/suite-core", .upToNextMinor(from: "27.1.0-dev.1")),
    ],
    targets: [
        .target(name: "LauncherCore", dependencies: [suiteCore]),
        .testTarget(name: "LauncherCoreTests", dependencies: ["LauncherCore"]),
        .executableTarget(name: "Launcher", dependencies: ["LauncherCore", suiteCore]),
    ]
)
