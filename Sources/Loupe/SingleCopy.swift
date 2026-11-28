import AppKit

/// One copy of Loupe runs at a time, release or development, since they share the bundle
/// identifier and the inventory file, and each copy saves its whole inventory over the file.
@MainActor
enum SingleCopy {
  /// Returns when no other copy is running, after quitting the others if the user chooses to.
  /// Otherwise exits.
  static func ensure() {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
      .filter { $0.processIdentifier != getpid() }
    guard !others.isEmpty else { return }
    let names = others.map { $0.bundleURL?.lastPathComponent ?? $0.localizedName ?? appName }
    NSApplication.shared.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "\(names.joined(separator: ", ")) is already open"
    alert.informativeText =
      "Every copy of Loupe uses the same saved inventory, so only one can be open at a time."
    alert.addButton(withTitle: "Quit \(names.count == 1 ? names[0] : "the Others")")
    alert.addButton(withTitle: "Cancel")
    guard alert.runModal() == .alertFirstButtonReturn else { exit(0) }
    for other in others { other.terminate() }
    let deadline = Date().addingTimeInterval(10)
    func running() -> Bool { others.contains { kill($0.processIdentifier, 0) == 0 } }
    while running() && Date() < deadline { usleep(100_000) }
    guard running() else { return }
    let failed = NSAlert()
    failed.messageText = "\(names.joined(separator: ", ")) didn't quit"
    failed.informativeText = "Quit it, then open this copy again."
    failed.runModal()
    exit(0)
  }
}
