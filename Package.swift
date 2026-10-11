// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "ArtifactLens",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "ArtifactLens", targets: ["ArtifactLens"])],
  targets: [
    .target(name: "ArtifactCore"),
    .executableTarget(name: "ArtifactLens", dependencies: ["ArtifactCore"]),
    .testTarget(name: "ArtifactCoreTests", dependencies: ["ArtifactCore"]),
    .testTarget(name: "ArtifactLensTests", dependencies: ["ArtifactLens", "ArtifactCore"]),
  ]
)
