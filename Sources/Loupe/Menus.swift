import AppKit
import Combine
import LoupeCore

/// The main menu and the menu bar icon. The icon stays while Loupe runs: with the dashboard
/// closed and the game in front, it's the quickest way back to the reader's controls.
@MainActor
final class Menus: NSObject, NSMenuItemValidation {
  private let model: Model
  private let autoPress: AutoPress
  private let updates: Updates
  private let showMainWindow: () -> Void
  private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
  private var observers: Set<AnyCancellable> = []

  init(model: Model, autoPress: AutoPress, updates: Updates, showMain: @escaping () -> Void) {
    self.model = model
    self.autoPress = autoPress
    self.updates = updates
    showMainWindow = showMain
    super.init()
    NSApp.mainMenu = mainMenu()
    statusItem.menu = statusMenu()
    // @Published sends before the property changes, so use the values it sends.
    model.$enabled.combineLatest(autoPress.$session.map(\.isOn))
      .removeDuplicates(by: ==)
      .sink { [weak self] reader, pressing in
        MainActor.assumeIsolated {
          self?.show(MenuBarIcon(readerEnabled: reader, autoPressOn: pressing))
        }
      }
      .store(in: &observers)
  }

  private func show(_ icon: MenuBarIcon) {
    guard let button = statusItem.button else { return }
    let image = NSImage(systemSymbolName: icon.symbol, accessibilityDescription: appName)
    image?.isTemplate = true
    button.image = image
    button.appearsDisabled = icon.dimmed
    button.toolTip = icon.toolTip
  }

  // MARK: Menus

  /// What's done in a hurry, mid-game. Settings stay in the main window and the main menu.
  private func statusMenu() -> NSMenu {
    let menu = NSMenu()
    add("Show Loupe", to: menu, action: #selector(showMain))
    menu.addItem(.separator())
    add("Choose Game Window…", to: menu, action: #selector(chooseWindow))
    add("Reader Enabled", to: menu, action: #selector(toggleEnabled))
    add("Overlay Expanded", to: menu, action: #selector(toggleExpanded))
    add("Reset Overlay Placement", to: menu, action: #selector(resetPlacement))
    menu.addItem(.separator())
    add("Save Snapshot", to: menu, action: #selector(saveSnapshot))
    add("Record Game Window", to: menu, action: #selector(toggleRecording))
    menu.addItem(.separator())
    add("Report Issue…", to: menu, action: #selector(reportIssue))
    add("Check for Updates…", to: menu, action: #selector(checkForUpdates))
    menu.addItem(.separator())
    add("Quit Loupe", to: menu, action: #selector(NSApplication.terminate(_:)), key: "q")
    return menu
  }

  private func mainMenu() -> NSMenu {
    let main = NSMenu()

    let app = submenu(appName, in: main)
    add(
      "About Loupe", to: app, action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
    app.addItem(.separator())
    add("Check for Updates…", to: app, action: #selector(checkForUpdates))
    add("Install Updates Automatically", to: app, action: #selector(toggleAutomaticUpdates))
    app.addItem(.separator())
    let services = NSMenu(title: "Services")
    app.addItem(withTitle: "Services", action: nil, keyEquivalent: "").submenu = services
    NSApp.servicesMenu = services
    app.addItem(.separator())
    add("Hide Loupe", to: app, action: #selector(NSApplication.hide(_:)), key: "h")
    add(
      "Hide Others", to: app, action: #selector(NSApplication.hideOtherApplications(_:)), key: "h",
      modifiers: [.command, .option])
    add(
      "Show All", to: app, action: #selector(NSApplication.unhideAllApplications(_:)))
    app.addItem(.separator())
    add("Quit Loupe", to: app, action: #selector(NSApplication.terminate(_:)), key: "q")

    let file = submenu("File", in: main)
    add("Import Inventory…", to: file, action: #selector(importInventory))
    add("Export Inventory…", to: file, action: #selector(exportInventory))
    file.addItem(.separator())
    add("Close", to: file, action: #selector(NSWindow.performClose(_:)), key: "w")

    let edit = submenu("Edit", in: main)
    add("Undo", to: edit, action: Selector(("undo:")), key: "z")
    add("Redo", to: edit, action: Selector(("redo:")), key: "Z")
    edit.addItem(.separator())
    add("Cut", to: edit, action: #selector(NSText.cut(_:)), key: "x")
    add("Copy", to: edit, action: #selector(NSText.copy(_:)), key: "c")
    add("Paste", to: edit, action: #selector(NSText.paste(_:)), key: "v")
    add("Select All", to: edit, action: #selector(NSText.selectAll(_:)), key: "a")

    let controls = submenu("Controls", in: main)
    add("Choose Game Window…", to: controls, action: #selector(chooseWindow))
    add("Reader Enabled", to: controls, action: #selector(toggleEnabled))
    add("Overlay Expanded", to: controls, action: #selector(toggleExpanded))
    add("Reset Overlay Placement", to: controls, action: #selector(resetPlacement))
    controls.addItem(.separator())
    add("Save Snapshot", to: controls, action: #selector(saveSnapshot))
    add("Record Game Window", to: controls, action: #selector(toggleRecording))
    controls.addItem(.separator())
    add("Auto-Press On", to: controls, action: #selector(toggleAutoPress))

    let window = submenu("Window", in: main)
    add(
      "Minimize", to: window, action: #selector(NSWindow.performMiniaturize(_:)), key: "m")
    add("Zoom", to: window, action: #selector(NSWindow.performZoom(_:)))
    window.addItem(.separator())
    add("Loupe", to: window, action: #selector(showMain), key: "1")
    window.addItem(.separator())
    add(
      "Bring All to Front", to: window, action: #selector(NSApplication.arrangeInFront(_:)))
    // Gives the window menu the system's tiling items. The dashboard is excluded from its list,
    // since the Loupe item above shows it.
    NSApp.windowsMenu = window

    let help = submenu("Help", in: main)
    add("Loupe Help", to: help, action: #selector(openHelp))
    add("Report Issue…", to: help, action: #selector(reportIssue))
    NSApp.helpMenu = help

    return main
  }

  private func submenu(_ title: String, in menu: NSMenu) -> NSMenu {
    let submenu = NSMenu(title: title)
    menu.addItem(withTitle: title, action: nil, keyEquivalent: "").submenu = submenu
    return submenu
  }

  /// Actions this class doesn't handle, the standard ones, go up the responder chain.
  private func add(
    _ title: String, to menu: NSMenu, action: Selector, key: String = "",
    modifiers: NSEvent.ModifierFlags = .command
  ) {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.target = responds(to: action) ? self : nil
    // macOS 27 adds symbols to items like Quit. The setting is in the macOS 27 SDK (Swift 6.4),
    // and CI's Xcode may be older than this Mac's.
    #if compiler(>=6.4)
      if #available(macOS 27, *) { item.preferredImageVisibility = .hidden }
    #endif
    menu.addItem(item)
  }

  // MARK: Actions

  func validateMenuItem(_ item: NSMenuItem) -> Bool {
    switch item.action {
    case #selector(chooseWindow), #selector(saveSnapshot): return model.enabled
    case #selector(toggleRecording):
      item.state = model.isRecording ? .on : .off
      return model.enabled
    case #selector(toggleEnabled): item.state = model.enabled ? .on : .off
    case #selector(toggleExpanded): item.state = model.overlayExpanded ? .on : .off
    case #selector(toggleAutoPress): item.state = autoPress.session.isOn ? .on : .off
    case #selector(reportIssue): return model.diagnostics.canRequest
    case #selector(toggleAutomaticUpdates):
      item.state = updates.automatic && updates.canInstall ? .on : .off
      item.toolTip =
        updates.canInstall ? nil : "Only copies installed from a release can update themselves."
      return updates.canInstall
    default: break
    }
    return true
  }

  @objc private func showMain() { showMainWindow() }
  @objc private func chooseWindow() { model.chooseWindow() }
  @objc private func toggleEnabled() { model.setEnabled(!model.enabled) }
  @objc private func toggleExpanded() { model.overlayExpanded.toggle() }
  @objc private func resetPlacement() { model.resetOverlayPlacement?() }
  @objc private func saveSnapshot() { model.saveSnapshot() }
  @objc private func toggleRecording() { model.toggleRecording() }
  @objc private func toggleAutoPress() { autoPress.toggle() }
  @objc private func importInventory() { model.importInventory() }
  @objc private func exportInventory() { model.exportInventory() }
  @objc private func reportIssue() { model.reportIssue() }
  @objc private func checkForUpdates() { updates.checkNow() }
  @objc private func toggleAutomaticUpdates() { updates.automatic.toggle() }
  @objc private func openHelp() {
    NSWorkspace.shared.open(URL(string: "https://github.com/xinding33/loupe#readme")!)
  }
}
