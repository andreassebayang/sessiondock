// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "ConnectionWorkbench", platforms: [.macOS(.v14)],
    products: [.library(name: "WorkbenchCore", targets: ["WorkbenchCore"]), .executable(name: "ConnectionWorkbench", targets: ["ConnectionWorkbench"])],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.3")],
    targets: [
        .target(name: "WorkbenchCore"),
        .target(name: "WorkbenchDesktop", dependencies: ["WorkbenchCore", .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .executableTarget(name: "ConnectionWorkbench", dependencies: ["WorkbenchDesktop"]),
        .testTarget(name: "WorkbenchCoreTests", dependencies: ["WorkbenchCore"]),
        .testTarget(name: "WorkbenchDesktopTests", dependencies: ["WorkbenchDesktop", "WorkbenchCore", .product(name: "SwiftTerm", package: "SwiftTerm")])
    ])
