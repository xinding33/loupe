// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Loupe",
  platforms: [.macOS(.v14)],
  products: [.executable(name: "Loupe", targets: ["Loupe"])],
  targets: [
    .target(name: "LoupeCore"),
    .executableTarget(name: "Loupe", dependencies: ["LoupeCore"]),
    .testTarget(name: "LoupeCoreTests", dependencies: ["LoupeCore"]),
    .testTarget(name: "LoupeTests", dependencies: ["Loupe", "LoupeCore"]),
  ]
)
