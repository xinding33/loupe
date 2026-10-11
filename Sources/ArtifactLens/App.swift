import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var window: NSWindow!
  private var overlay: OverlayController!
  private var shortcuts: OverlayShortcuts!
  private let shortcutBackend = CarbonShortcutBackend()
  private var model: Model!

  func applicationDidFinishLaunching(_ notification: Notification) {
    model = Model()
    let menu = NSMenu()
    let appItem = NSMenuItem()
    menu.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(
      withTitle: "Show Artifact Lens", action: #selector(showMain), keyEquivalent: "1"
    ).target = self
    appMenu.addItem(
      withTitle: "Expand / collapse overlay", action: #selector(toggleExpanded), keyEquivalent: ""
    ).target = self
    appMenu.addItem(
      withTitle: "Enable / disable reader", action: #selector(toggleEnabled), keyEquivalent: ""
    ).target = self
    appMenu.addItem(
      withTitle: "Reset overlay placement", action: #selector(resetPlacement), keyEquivalent: ""
    ).target = self
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Report issue", action: #selector(reportIssue), keyEquivalent: "")
      .target = self
    appMenu.addItem(
      withTitle: "Quit Artifact Lens", action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q")
    let editItem = NSMenuItem()
    editItem.title = "Edit"
    menu.addItem(editItem)
    let edit = NSMenu(title: "Edit")
    editItem.submenu = edit
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(
      withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    NSApplication.shared.mainMenu = menu

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1080, height: 800),
      styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
    )
    window.title = "Artifact Lens"
    window.contentView = NSHostingView(rootView: Dashboard(model: model))
    window.isReleasedWhenClosed = false
    window.center()
    window.makeKeyAndOrderFront(nil)
    model.diagnostics.present = { [weak self] in
      self?.window.makeKeyAndOrderFront(nil)
      NSApplication.shared.activate(ignoringOtherApps: true)
    }

    overlay = OverlayController(model: model)
    shortcuts = OverlayShortcuts(backend: shortcutBackend)
    shortcuts.expand = { [weak self] in self?.model.overlayExpanded.toggle() }
    shortcuts.toggleEnabled = { [weak self] in
      guard let self else { return }
      model.setEnabled(!model.enabled)
    }
    model.applyShortcuts = { [weak self] in
      guard let self else { return }
      do {
        try shortcuts.configure(expand: model.expandShortcut, enable: model.enableShortcut)
        UserDefaults.standard.set(model.expandShortcut, forKey: "expandShortcut")
        UserDefaults.standard.set(model.enableShortcut, forKey: "enableShortcut")
        model.shortcutStatus = "Global shortcuts registered. Keys use US keyboard positions."
      } catch {
        model.shortcutStatus = error.localizedDescription
      }
    }
    model.applyShortcuts?()
    NSApplication.shared.activate(ignoringOtherApps: true)
  }

  @objc private func showMain() { window.makeKeyAndOrderFront(nil) }
  @objc private func toggleExpanded() { model.overlayExpanded.toggle() }
  @objc private func toggleEnabled() { model.setEnabled(!model.enabled) }
  @objc private func resetPlacement() { model.resetOverlayPlacement?() }
  @objc private func reportIssue() { model.reportIssue() }
  func applicationWillTerminate(_ notification: Notification) {
    model.setEnabled(false)
    shortcutBackend.close()
  }
  func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool
  {
    showMain()
    return true
  }
}

@main
struct ArtifactLensApp {
  @MainActor static func main() {
    DiagnosticCommand.dispatchIfRequested()
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
    withExtendedLifetime(delegate) {}
  }
}
