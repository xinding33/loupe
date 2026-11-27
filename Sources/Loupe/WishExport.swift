import AppKit
import LoupeCore
import UniformTypeIdentifiers

/// File > Export Wish History…: reads the link the game saved when Wish > History was last opened,
/// downloads every pull newer than the ones Loupe has, adds them to Loupe's saved history and
/// writes that as a UIGF file. It talks only to HoYoverse's history API and never to the game.
@MainActor
final class WishExport {
  /// From choosing the command until the file is written, panels included, so an update waits.
  private(set) var isRunning = false
  var status: ((String) -> Void)?
  var issue: ((String) -> Void)?
  var banner: ((String) -> Void)?

  private let history: URL
  private let defaults: UserDefaults
  private static let gameFolderKey = "wishGameFolder"

  init(
    history: URL = URL.applicationSupportDirectory.appending(path: "Loupe/wishes.json"),
    defaults: UserDefaults = .standard
  ) {
    self.history = history
    self.defaults = defaults
  }

  func export() {
    guard !isRunning else { return }
    isRunning = true
    Task {
      defer { isRunning = false }
      do {
        try await run()
      } catch {
        status?("Wish history wasn't exported.")
        issue?(error.localizedDescription)
      }
    }
  }

  private func run() async throws {
    guard let folders = gameDataFolders() else { return }
    guard let cache = WishCache.cacheFile(in: folders) else { throw WishError.noLink }
    let links = try await WishCache.links(in: cache)
    guard !links.isEmpty else { throw WishError.noLink }
    // Read now so a damaged history stops the export before anything is downloaded. `save`
    // reads it again before writing.
    let history = history
    let known = try await Self.knownIDs(in: history)
    guard let destination = askForDestination() else { return }

    status?("Downloading wish history…")
    let report: @Sendable (Int) -> Void = { [weak self] count in
      Task { @MainActor in
        // A late update would cover the result.
        guard let self, self.isRunning else { return }
        self.status?("Downloading wish history: \(count) new pulls…")
      }
    }
    let download = try await WishDownload().run(links, known: known, progress: report)
    let saved = try await WishHistory.save(
      download, to: history, export: destination, app: appName,
      version: appVersion.description)
    let account = saved.uid.map { " for UID \($0)" } ?? ""
    status?(
      "Exported \(saved.total) pulls\(account), \(saved.added) of them new, to \(destination.path)."
    )
    banner?("Wish history exported")
  }

  private nonisolated static func knownIDs(in file: URL) async throws -> Set<String> {
    guard FileManager.default.fileExists(atPath: file.path) else { return [] }
    return try WishHistory.read(from: file).knownIDs
  }

  /// The game's data folders: the one chosen before and Yaagl's, else one the user picks.
  private func gameDataFolders() -> [URL]? {
    let saved = defaults.string(forKey: Self.gameFolderKey).map { URL(filePath: $0) }
    let found = ([saved].compactMap { $0 } + WishCache.yaaglGameFolders()).compactMap {
      WishCache.dataFolder(for: $0)
    }
    if !found.isEmpty { return found }
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.message =
      "Choose the Genshin Impact game folder, the one with GenshinImpact_Data in it."
    panel.prompt = "Choose"
    while panel.runModal() == .OK, let folder = panel.url {
      if let data = WishCache.dataFolder(for: folder) {
        defaults.set(folder.path, forKey: Self.gameFolderKey)
        return [data]
      }
      panel.message =
        "That folder has no GenshinImpact_Data with a webCaches folder. Choose the game folder."
    }
    return nil
  }

  private func askForDestination() -> URL? {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue =
      "Genshin-wishes-\(Date.now.formatted(.iso8601.year().month().day())).json"
    panel.message = "Saves every pull Loupe has, as UIGF v4, for wish trackers."
    return panel.runModal() == .OK ? panel.url : nil
  }
}
