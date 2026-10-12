// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeychainStore",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "KeychainStore", targets: ["KeychainStore"]),
    ],
    targets: [
        .target(name: "KeychainStore"),
    ]
)
