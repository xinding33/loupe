import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private var overlay: OverlayController!
  private var shortcuts: OverlayShortcuts!
  private let shortcutBackend = CarbonShortcutBackend()
  private var model: Model!
  private var autoPress: AutoPress!
  private let updates = Updates()
  private var menus: Menus!
  private let hud = HUD()

  func applicationDidFinishLaunching(_ notification: Notification) {
    model = Model()
    model.banner = { [hud] in hud.show($0) }
    autoPress = AutoPress(hud: hud)
    autoPress.overlayShortcuts = { [weak self] in
      guard let self else { return [] }
      return [
        model.expandShortcut, model.enableShortcut, model.snapshotShortcut, model.recordShortcut,
      ].compactMap { try? OverlayShortcut($0) }
    }
    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1080, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "Loupe"
    window.contentView = NSHostingView(
      rootView: Dashboard(model: model, autoPress: autoPress))
    window.isReleasedWhenClosed = false
    window.isExcludedFromWindowsMenu = true
    window.tabbingMode = .disallowed
    window.center()
    window.makeKeyAndOrderFront(nil)
    model.diagnostics.present = { [weak self] in
      self?.window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    menus = Menus(model: model, autoPress: autoPress, updates: updates) { [weak self] in
      self?.showMain()
    }

    overlay = OverlayController(model: model)
    shortcuts = OverlayShortcuts(backend: shortcutBackend)
    shortcuts.expand = { [weak self] in self?.model.overlayExpanded.toggle() }
    shortcuts.toggleEnabled = { [weak self] in
      guard let self else { return }
      model.setEnabled(!model.enabled)
    }
    shortcuts.snapshot = { [weak self] in self?.model.saveSnapshot() }
    shortcuts.toggleRecording = { [weak self] in self?.model.toggleRecording() }
    model.applyShortcuts = { [weak self] in
      guard let self else { return }
      do {
        try shortcuts.configure(
          expand: model.expandShortcut, enable: model.enableShortcut,
          snapshot: model.snapshotShortcut, record: model.recordShortcut)
        UserDefaults.standard.set(model.expandShortcut, forKey: "expandShortcut")
        UserDefaults.standard.set(model.enableShortcut, forKey: "enableShortcut")
        UserDefaults.standard.set(model.snapshotShortcut, forKey: "snapshotShortcut")
        UserDefaults.standard.set(model.recordShortcut, forKey: "recordShortcut")
        model.shortcutStatus = "Global shortcuts registered. Keys use US keyboard positions."
      } catch {
        model.shortcutStatus = error.localizedDescription
      }
    }
    model.applyShortcuts?()
    if let problem = Migration.problem {
      model.issue = [model.issue, problem].compactMap { $0 }.joined(separator: " ")
    }
    updates.isBusy = { [weak self] in
      guard let self else { return false }
      return model.isBusy || autoPress.session.isOn
    }
    updates.start()
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  private func showMain() {
    // Activating first, since the menu bar icon's menu can open while another app is in front.
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }
  func applicationWillTerminate(_ notification: Notification) {
    model.setEnabled(false)
    autoPress.shutdown()
    shortcutBackend.close()
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showMain()
    return true
  }
}

@main
struct LoupeApp {
  @MainActor static func main() {
    // Command-line modes run before AppKit starts, so they work over SSH and from agents.
    if CommandLine.arguments.contains("--diagnose") { Diagnose.run() }
    DiagnosticCommand.dispatchIfRequested()
    Migration.run()
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
  }
}
