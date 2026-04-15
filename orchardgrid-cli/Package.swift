// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "orchardgrid-cli",
  platforms: [.macOS(.v26)],  // FoundationModels requires macOS 26
  products: [
    .executable(name: "og", targets: ["og"])
  ],
  dependencies: [
    // OrchardGridCore hosts the on-device primitives shared with the
    // OrchardGrid menu-bar app (context trimming, token counting,
    // transcript assembly, summary-based trim fallback).
    .package(path: "../Packages/OrchardGridCore"),
    .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
  ],
  targets: [
    .target(
      name: "ogKit",
      dependencies: [
        .product(name: "OrchardGridCore", package: "OrchardGridCore"),
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
      ],
      path: "Sources/ogKit"),
    .executableTarget(
      name: "og", dependencies: ["ogKit"], path: "Sources/og"),
    .testTarget(
      name: "ogKitTests", dependencies: ["ogKit"], path: "Tests/ogKitTests"),
  ]
)
