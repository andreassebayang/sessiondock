// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ConnectionWorkbench", platforms: [.macOS(.v14)],
    products: [.library(name: "WorkbenchCore", targets: ["WorkbenchCore"]), .executable(name: "ConnectionWorkbench", targets: ["ConnectionWorkbench"])],
    targets: [
        .target(name: "WorkbenchCore"),
        .target(name: "WorkbenchDesktop", dependencies: ["WorkbenchCore"]),
        .executableTarget(name: "ConnectionWorkbench", dependencies: ["WorkbenchDesktop"]),
        .testTarget(name: "WorkbenchCoreTests", dependencies: ["WorkbenchCore"]),
        .testTarget(name: "WorkbenchDesktopTests", dependencies: ["WorkbenchDesktop", "WorkbenchCore"])
    ])
