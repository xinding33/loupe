import ApplicationServices
import Foundation
import LoupeCore

/// `Loupe --diagnose` prints what an agent or a bug report needs, then exits. It only reads:
/// it never prompts for permissions or changes settings.
enum Diagnose {
  static func run() -> Never {
    let app = Bundle.main.bundleURL
    let inventory = URL.applicationSupportDirectory.appending(path: "\(appName)/inventory.json")
    let saved = (try? Inventory.read(from: inventory))?.artifacts.count
    let lines = [
      "\(appName) \(appVersion) at \(app.path)",
      "Bundle identifier: \(bundleID)",
      "Release build: \(Updater.isRelease(app) ? "yes" : "no")",
      "Developer ID signed: \(Updater.isDeveloperIDSigned(app) ? "yes" : "no")",
      "Installs updates: \(Updater.canInstallUpdates(into: app) ? "yes" : "no")",
      "Saved inventory: \(saved.map { "\($0) artifacts" } ?? "none") at \(inventory.path)",
      // Capture goes through the sharing picker, which needs no Screen Recording grant. Run from a
      // terminal, the app has the terminal's grants, so this reports the terminal's.
      "Accessibility (auto-press): \(AXIsProcessTrusted() ? "granted" : "not granted")",
    ]
    print(lines.joined(separator: "\n"))
    exit(0)
  }
}

/// Carries over the inventory and settings of Artifact Lens, the app's name before Loupe.
enum Migration {
  private static let doneKey = "importedArtifactLensSettings"

  static func run() {
    let support = URL.applicationSupportDirectory
    do {
      let folder = support.appending(path: appName, directoryHint: .isDirectory)
      if try LegacyData.moveFolder(in: support, to: folder) {
        log.info("Moved the Artifact Lens folder to \(folder.path, privacy: .public)")
      }
    } catch {
      log.error(
        "Couldn't move the Artifact Lens folder: \(error.localizedDescription, privacy: .public)")
    }
    let defaults = UserDefaults.standard
    guard !defaults.bool(forKey: doneKey) else { return }
    if let old = defaults.persistentDomain(forName: LegacyData.defaultsDomain) {
      let keys = LegacyData.copySettings(old, into: defaults)
      log.info("Imported Artifact Lens settings: \(keys.joined(separator: ", "), privacy: .public)")
    }
    defaults.set(true, forKey: doneKey)
  }
}
