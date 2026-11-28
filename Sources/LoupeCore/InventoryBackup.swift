import Foundation

/// Copies of the inventory file from before a launch's first save, so a build that saves
/// something wrong, a development build especially, can be rolled back from Finder.
public enum InventoryBackup {
  public static let folderName = "Inventory backups"
  public static let kept = 10

  /// Copies `file` into `folder` as `inventory <time> <label>.json` and removes all but the
  /// newest `keep` copies. Does nothing when there's no file yet. Returns the copy.
  @discardableResult
  public static func copy(
    _ file: URL, into folder: URL, label: String, at time: Date = Date(), keep: Int = kept,
    files: FileManager = .default
  ) throws -> URL? {
    guard files.fileExists(atPath: file.path) else { return nil }
    try files.createDirectory(at: folder, withIntermediateDirectories: true)
    let stamp = time.formatted(
      Date.VerbatimFormatStyle(
        format:
          "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)",
        timeZone: .current, calendar: Calendar(identifier: .gregorian)))
    let safeLabel = label.replacingOccurrences(of: "/", with: "-")
    var copy = folder.appending(path: "inventory \(stamp) \(safeLabel).json")
    var suffix = 2
    while files.fileExists(atPath: copy.path) {
      copy = folder.appending(path: "inventory \(stamp) \(safeLabel) \(suffix).json")
      suffix += 1
    }
    try files.copyItem(at: file, to: copy)
    // The time leads each name, so names sort oldest first.
    let copies = try files.contentsOfDirectory(atPath: folder.path)
      .filter { $0.hasPrefix("inventory ") && $0.hasSuffix(".json") }
      .sorted()
    for name in copies.dropLast(keep) {
      try? files.removeItem(at: folder.appending(path: name))
    }
    return copy
  }
}
