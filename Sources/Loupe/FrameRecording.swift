import Foundation
import ImageIO
import LoupeCore
import UniformTypeIdentifiers

final class FrameRecording {
  let finish: @Sendable (String) -> Void
  private let folder = URL.applicationSupportDirectory.appending(
    path: "Loupe/Diagnostics/\(UUID().uuidString)", directoryHint: .isDirectory)
  private var count = 0

  init(finish: @escaping @Sendable (String) -> Void) { self.finish = finish }

  func append(_ image: CGImage) throws -> Bool {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appending(path: String(format: "%03d.png", count))
    guard
      let output = CGImageDestinationCreateWithURL(
        file as CFURL, UTType.png.identifier as CFString, 1, nil)
    else {
      throw ArtifactError("Cannot create a diagnostic image.")
    }
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else {
      throw ArtifactError("Cannot write a diagnostic image.")
    }
    count += 1
    if count == 40 { finish("Saved 40 local frames: \(folder.path)") }
    return count == 40
  }
}
