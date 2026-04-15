// swift-tools-version: 6.2
import PackageDescription

// OrchardGridCore — pure on-device AI primitives shared between the
// OrchardGrid menu-bar app (Xcode target) and the `og` CLI (sibling
// SPM package under orchardgrid-cli/). Everything here is pure Swift
// on top of FoundationModels: no UI, no Clerk, no HTTP. Tests run in
// this package's own target, so they execute in CI without Apple
// development signing.

let package = Package(
  name: "OrchardGridCore",
  platforms: [.macOS(.v26), .iOS(.v26)],
  products: [
    .library(name: "OrchardGridCore", targets: ["OrchardGridCore"])
  ],
  targets: [
    .target(name: "OrchardGridCore"),
    .testTarget(
      name: "OrchardGridCoreTests",
      dependencies: ["OrchardGridCore"]
    ),
  ]
)
