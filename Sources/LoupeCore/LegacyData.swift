import Foundation

/// Carries data over from Artifact Lens, the app's name before it became Loupe.
public enum LegacyData {
  public static let defaultsDomain = "local.artifactlens"
  public static let folderName = "ArtifactLens"

  /// Moves the old Application Support folder to `folder`, unless `folder` already exists.
  /// Returns whether it moved anything.
  @discardableResult
  public static func moveFolder(
    in support: URL, to folder: URL, files: FileManager = .default
  ) throws -> Bool {
    let old = support.appending(path: folderName, directoryHint: .isDirectory)
    guard files.fileExists(atPath: old.path), !files.fileExists(atPath: folder.path) else {
      return false
    }
    try files.moveItem(at: old, to: folder)
    return true
  }

  /// Copies settings from the old defaults domain that `defaults` doesn't have yet.
  /// Returns the keys it copied.
  @discardableResult
  public static func copySettings(_ old: [String: Any], into defaults: UserDefaults) -> [String] {
    let copied = old.keys.filter { defaults.object(forKey: $0) == nil }.sorted()
    for key in copied { defaults.set(old[key], forKey: key) }
    return copied
  }
}
