// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "RoyalVNCKit", platforms: [.macOS(.v14)],
    products: [.library(name: "RoyalVNCKit", type: .dynamic, targets: ["RoyalVNCKit"])],
    dependencies: [.package(url: "https://github.com/royalapplications/CryptoSwift.git", revision: "a59b4d91ebb22011656c830f874fe7152e183a57")],
    targets: [
        .target(name: "Z", linkerSettings: [.linkedLibrary("z")]),
        .target(name: "d3des"), .target(name: "RoyalVNCKitC"),
        .target(name: "RoyalVNCKit", dependencies: ["RoyalVNCKitC", "d3des", "Z", .product(name: "CryptoSwift", package: "CryptoSwift")], swiftSettings: [.swiftLanguageMode(.v5)])
    ])
