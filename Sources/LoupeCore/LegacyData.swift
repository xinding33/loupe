import Foundation

/// Carries data over from Artifact Lens, the app's name before it became Loupe.
public enum LegacyData {
  public static let defaultsDomain = "local.artifactlens"
  public static let folderName = "ArtifactLens"

  /// What `moveFolder` did, by path relative to the old folder.
  public struct Move: Equatable, Sendable {
    public var moved: [String] = []
    /// Items left behind because the new folder already has an item of that name.
    public var kept: [String] = []

    public init(moved: [String] = [], kept: [String] = []) {
      self.moved = moved
      self.kept = kept
    }
  }

  /// Moves everything in the old Application Support folder into `folder`, merging folders and
  /// never replacing an item that `folder` already has. The old folder is removed once empty.
  /// Safe to run on every launch: a move that fails part way is finished by the next one.
  @discardableResult
  public static func moveFolder(
    in support: URL, to folder: URL, files: FileManager = .default
  ) throws -> Move {
    let old = support.appending(path: folderName, directoryHint: .isDirectory)
    var result = Move()
    guard files.fileExists(atPath: old.path) else { return result }
    try merge(old, into: folder, path: "", files: files, result: &result)
    return result
  }

  private static func merge(
    _ source: URL, into target: URL, path: String, files: FileManager, result: inout Move
  ) throws {
    var isFolder: ObjCBool = false
    if !files.fileExists(atPath: target.path, isDirectory: &isFolder) {
      try files.moveItem(at: source, to: target)
      result.moved.append(path.isEmpty ? "." : path)
      return
    }
    var sourceIsFolder: ObjCBool = false
    files.fileExists(atPath: source.path, isDirectory: &sourceIsFolder)
    guard isFolder.boolValue, sourceIsFolder.boolValue else {
      result.kept.append(path)
      return
    }
    for name in try files.contentsOfDirectory(atPath: source.path).sorted() {
      try merge(
        source.appending(path: name), into: target.appending(path: name),
        path: path.isEmpty ? name : "\(path)/\(name)", files: files, result: &result)
    }
    if try files.contentsOfDirectory(atPath: source.path).isEmpty {
      try files.removeItem(at: source)
    }
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
