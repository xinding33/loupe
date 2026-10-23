import AppKit
import ArtifactCore

/// Presses a key repeatedly while a chosen app is in front: F in GeForce NOW to start with, for
/// skipping dialogue. Ported from Mash. It works whether or not the reader is enabled.
@MainActor
final class AutoPress: ObservableObject {
  static let defaultsKey = "autoPress"

  @Published var settings: AutoPressSettings {
    didSet {
      guard settings != oldValue else { return }
      defaults.set(try? JSONEncoder().encode(settings), forKey: Self.defaultsKey)
      apply()
    }
  }
  @Published private(set) var session = AutoPressSession()
  @Published private(set) var targetFrontmost = false
  @Published private(set) var accessibilityGranted = AXIsProcessTrusted()
  @Published private(set) var triggerIssue: String?
  /// The overlay's shortcuts, so the toggle can't be recorded as one of them.
  var overlayShortcuts: () -> [OverlayShortcut] = { [] }

  private let defaults: UserDefaults
  private let presser = AutoPresser()
  private let monitor = AutoPressTriggerMonitor()
  private let hud = AutoPressHUD()
  private var autoOff: DispatchSourceTimer?
  private var accessibilityPoll: DispatchSourceTimer?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    settings = AutoPressSettings.decode(defaults.data(forKey: Self.defaultsKey))
    monitor.onTrigger = { [weak self] in self?.toggle() }
    // Lives as long as the app, so the observer is never removed.
    NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
    ) { [weak self] _ in MainActor.assumeIsolated { self?.apply() } }
    apply()
  }

  var keyName: String { autoPressKeyName(settings.pressedKeyCode) }

  func status(at date: Date) -> String {
    session.status(targetFrontmost: targetFrontmost, at: date, settings, keyName: keyName)
  }

  /// Turns auto-press on or off. Turning on asks for Accessibility first and stays off without it.
  func setOn(_ on: Bool) {
    guard on != session.isOn else { return }
    if on {
      guard requestAccessibility() else { return }
      session.turnOn(at: Date())
    } else {
      session.turnOff()
    }
    apply()
  }

  /// The toggle shortcut and menu item. The HUD confirms it over a full-screen game.
  func toggle() {
    let wasOn = session.isOn
    setOn(!wasOn)
    if session.isOn {
      hud.show("Auto-press on")
    } else {
      hud.show(wasOn ? "Auto-press off" : "Auto-press needs Accessibility access")
    }
  }

  /// Releases a key that's down, so quitting mid-press doesn't leave it held in the game.
  func shutdown() {
    session.turnOff()
    presser.stop()
    monitor.update(trigger: settings.trigger, active: false)
  }

  /// Why `trigger` can't be the toggle, or nil if it can.
  func rejection(forTrigger trigger: AutoPressTrigger) -> String? {
    if trigger.conflicts(withPressedKey: settings.pressedKeyCode) {
      return "That's the key being pressed, so it can't also be the toggle on its own."
    }
    if overlayShortcuts().contains(where: trigger.matches) {
      return "That's one of the overlay's shortcuts."
    }
    return nil
  }

  func rejection(forPressedKey keyCode: UInt16) -> String? {
    settings.trigger.conflicts(withPressedKey: keyCode)
      ? "That key is the toggle, so it can't also be the key to press." : nil
  }

  func refreshAccessibility() {
    let granted = AXIsProcessTrusted()
    if granted {
      accessibilityPoll?.cancel()
      accessibilityPoll = nil
    }
    guard granted != accessibilityGranted else { return }
    accessibilityGranted = granted
    // A mouse-button toggle could not be installed without it.
    apply()
  }

  func openAccessibilitySettings() {
    _ = requestAccessibility()
    if let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
      NSWorkspace.shared.open(url)
    }
  }

  private func requestAccessibility() -> Bool {
    // The value of kAXTrustedCheckOptionPrompt, which Swift 6 won't read because it's a global var.
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    let granted = AXIsProcessTrustedWithOptions(options)
    if granted != accessibilityGranted { accessibilityGranted = granted }
    if !granted { pollAccessibility() }
    return granted
  }

  /// Notices the grant in System Settings without asking for a restart.
  private func pollAccessibility() {
    guard accessibilityPoll == nil else { return }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 2, repeating: 2)
    timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.refreshAccessibility() }
    }
    timer.resume()
    accessibilityPoll = timer
  }

  /// Brings the presser, toggle and auto-off timer in line with the current state.
  private func apply() {
    let frontmost =
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == settings.target.bundleID
    if frontmost != targetFrontmost { targetFrontmost = frontmost }
    let now = Date()
    if session.isExpired(at: now, settings) {
      session.turnOff()
      hud.show("Auto-press off (timer)")
    }

    monitor.update(trigger: settings.trigger, active: frontmost)
    if monitor.issue != triggerIssue { triggerIssue = monitor.issue }

    if session.shouldPress(targetFrontmost: frontmost, at: now, settings) {
      presser.start(settings)
    } else {
      presser.stop()
    }

    autoOff?.cancel()
    autoOff = nil
    if let date = session.autoOffDate(settings) {
      // Wall time keeps counting while the Mac sleeps, like the timer the user sees.
      let timer = DispatchSource.makeTimerSource(queue: .main)
      timer.schedule(wallDeadline: .now() + max(0, date.timeIntervalSince(now)))
      timer.setEventHandler { [weak self] in
        MainActor.assumeIsolated {
          guard let self, self.session.isOn else { return }
          self.session.turnOff()
          self.hud.show("Auto-press off (timer)")
          self.apply()
        }
      }
      timer.resume()
      autoOff = timer
    }
  }
}
