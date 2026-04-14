// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "orchardgrid-cli",
  platforms: [.macOS(.v26)],  // FoundationModels requires macOS 26
  products: [
    .executable(name: "og", targets: ["og"])
  ],
  targets: [
    .target(name: "ogKit", path: "Sources/ogKit"),
    .executableTarget(
      name: "og", dependencies: ["ogKit"], path: "Sources/og"),
    .testTarget(
      name: "ogKitTests", dependencies: ["ogKit"], path: "Tests/ogKitTests"),
  ]
)
