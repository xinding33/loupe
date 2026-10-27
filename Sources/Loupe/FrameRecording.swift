import Foundation
import ImageIO
import LoupeCore
import UniformTypeIdentifiers

/// Where snapshots and recordings of the shared window go, and how they're written.
enum CaptureFiles {
  static let folder = URL.applicationSupportDirectory.appending(
    path: "Loupe/Diagnostics", directoryHint: .isDirectory)

  /// A name that sorts by time and reads well in Finder, such as `2026-10-26 at 18.30.12`.
  static func stamp(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
    return formatter.string(from: date)
  }

  /// `name` in the folder, numbered when two land in the same second.
  static func unused(_ name: String, extension ext: String) -> URL {
    let dot = ".\(ext)"
    var url = folder.appending(path: name + dot)
    var number = 2
    while FileManager.default.fileExists(atPath: url.path) {
      url = folder.appending(path: "\(name) \(number)\(dot)")
      number += 1
    }
    return url
  }

  static func png(_ image: CGImage) throws -> Data {
    let data = NSMutableData()
    guard
      let output = CGImageDestinationCreateWithData(
        data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
    else { throw ArtifactError("Cannot encode the game frame.") }
    CGImageDestinationAddImage(output, image, nil)
    guard CGImageDestinationFinalize(output) else {
      throw ArtifactError("Cannot encode the game frame.")
    }
    return data as Data
  }

  /// Saves one frame as a snapshot and returns where it went and its PNG data.
  static func saveSnapshot(_ image: CGImage) throws -> (url: URL, png: Data) {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = unused("Snapshot \(stamp())", extension: "png")
    let data = try png(image)
    try data.write(to: url, options: .withoutOverwriting)
    return (url, data)
  }
}

/// Numbered PNG frames of the shared window, until stopped or `limit` is reached. Used only on
/// the capture queue, apart from `folder`.
final class FrameRecording: @unchecked Sendable {
  /// About two minutes at two frames a second; a full-window PNG can be several megabytes.
  static let limit = 240
  let folder: URL
  /// Reports a recording that filled up or failed, on the capture queue.
  let ended: @Sendable (FrameRecording, String) -> Void
  private(set) var count = 0
  private var outcome: String?

  init(folder: URL, ended: @escaping @Sendable (FrameRecording, String) -> Void) {
    self.folder = folder
    self.ended = ended
  }

  /// Creates a new, empty folder, so two recordings started in the same second can't share one.
  static func reserveFolder() throws -> URL {
    let files = FileManager.default
    try files.createDirectory(at: CaptureFiles.folder, withIntermediateDirectories: true)
    let name = "Recording \(CaptureFiles.stamp())"
    for number in 1...100 {
      let url = CaptureFiles.folder.appending(path: number == 1 ? name : "\(name) \(number)")
      do {
        try files.createDirectory(at: url, withIntermediateDirectories: false)
        return url
      } catch CocoaError.fileWriteFileExists {
        continue
      }
    }
    throw ArtifactError("Cannot create a recording folder.")
  }

  /// Returns true once the recording is full.
  func append(_ image: CGImage) throws -> Bool {
    let file = folder.appending(path: String(format: "%03d.png", count))
    try CaptureFiles.png(image).write(to: file, options: .withoutOverwriting)
    count += 1
    return count == Self.limit
  }

  /// The folder, once it holds a frame.
  var saved: URL? { count > 0 ? folder : nil }

  /// Ends it and says how it went. Only the first call counts, so an empty folder is removed
  /// once and never after a new recording has reserved the same name.
  @discardableResult
  func finish(failure: Error? = nil) -> String {
    if let outcome { return outcome }
    if count == 0 { try? FileManager.default.removeItem(at: folder) }
    let message =
      if let failure {
        "Recording failed: \(failure.localizedDescription)"
      } else {
        switch count {
        case 0: "Recording stopped before a frame arrived."
        case Self.limit: "Saved \(count) frames, the limit: \(folder.path)"
        default: "Saved \(count) frames: \(folder.path)"
        }
      }
    outcome = message
    return message
  }
}
