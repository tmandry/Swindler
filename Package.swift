// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Swindler",
    platforms: [
        .macOS(.v10_12),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "Swindler",
            targets: ["Swindler"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/tmandry/AXSwift.git", from: "0.3.2"),
        .package(url: "https://github.com/mxcl/PromiseKit.git", from: "6.13.3"),
        .package(url: "https://github.com/Quick/Quick.git", from: "4.0.0"),
        .package(url: "https://github.com/Quick/Nimble.git", from: "7.3.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "Swindler",
            dependencies: ["AXSwift", "PromiseKit"],
            path: "Sources"),
        .target(name: "SwindlerExample",
            dependencies: ["Swindler"],
            path: "SwindlerExample"),
        .testTarget(
            name: "SwindlerTests",
            dependencies: ["Swindler", "PromiseKit", "Quick", "Nimble"],
            path: "SwindlerTests"),
    ]
)
