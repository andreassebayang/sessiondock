// swift-tools-version: 6.0
import PackageDescription
import Foundation
let nativePrefix = ProcessInfo.processInfo.environment["SESSIONDOCK_LIBSSH2_PREFIX"] ?? (FileManager.default.fileExists(atPath: "/opt/homebrew/opt/libssh2") ? "/opt/homebrew/opt/libssh2" : "/usr/local/opt/libssh2")
let package = Package(name: "ConnectionWorkbench", platforms: [.macOS(.v14)],
    products: [.library(name: "WorkbenchCore", targets: ["WorkbenchCore"]), .executable(name: "ConnectionWorkbench", targets: ["ConnectionWorkbench"])],
    dependencies: [.package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.99.3"), .package(path: "Sources/VNCVendor"), .package(url: "https://github.com/steelbrain/RDPKit.git", exact: "0.9.0")],
    targets: [
        .target(name: "WorkbenchCore"),
        .target(name: "CSFTP", cSettings: [.unsafeFlags(["-I" + nativePrefix + "/include"])], linkerSettings: [.unsafeFlags(["-L" + nativePrefix + "/lib"]), .linkedLibrary("ssh2")]),
        .target(name: "WorkbenchDesktop", dependencies: ["WorkbenchCore", "CSFTP", .product(name: "RoyalVNCKit", package: "VNCVendor"), .product(name: "RDPKit", package: "RDPKit"), .product(name: "RDPKitAppKit", package: "RDPKit"), .product(name: "SwiftTerm", package: "SwiftTerm")]),
        .executableTarget(name: "ConnectionWorkbench", dependencies: ["WorkbenchDesktop"]),
        .testTarget(name: "WorkbenchCoreTests", dependencies: ["WorkbenchCore"]),
        .testTarget(name: "WorkbenchDesktopTests", dependencies: ["WorkbenchDesktop", "WorkbenchCore", .product(name: "SwiftTerm", package: "SwiftTerm")])
    ])
