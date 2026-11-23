import AppKit
import LoupeCore

/// Repeatedly presses a key, but only while the target app is frontmost.
///
/// Presses run on their own high-priority queue, so a busy main thread can't delay them. `start`
/// and `stop` may be called from any thread.
final class AutoPresser: @unchecked Sendable {
  private struct Configuration: Equatable {
    let keyCode: CGKeyCode
    let interval: TimeInterval
    let hold: TimeInterval
    let bundleID: String
  }

  /// Whether the target app receives key events right now.
  enum Focus {
    case target, other
    /// The target looks frontmost, but the check that confirms it failed. Nothing is pressed.
    case unconfirmed
  }

  /// Posts a key-down (`true`) or key-up (`false`).
  typealias Post = @Sendable (CGKeyCode, Bool) -> Void
  /// Where the app with this bundle identifier stands.
  typealias FocusCheck = @Sendable (String) -> Focus

  /// How long focus must stay unconfirmed before `onUnconfirmed` is told.
  static let unconfirmedDelay: TimeInterval = 1

  private let queue = DispatchQueue(label: "Loupe.AutoPress", qos: .userInteractive)
  /// Key-ups get their own queue, so a slow focus check for the next press can't hold a key down.
  private let releases = DispatchQueue(label: "Loupe.AutoPress.release", qos: .userInteractive)
  private let post: Post
  private let focus: FocusCheck
  /// Guards everything below, which `stop` changes from the caller's thread.
  private let lock = NSLock()
  private var timer: DispatchSourceTimer?
  private var configuration: Configuration?
  /// Bumped by `stop`, so a press already under way when it's called is dropped.
  private var generation = 0
  /// The key still held down, and the press that put it down.
  private var held: (keyCode: CGKeyCode, press: Int)?
  private var presses = 0
  /// When focus was first unconfirmed in the current run of such presses.
  private var unconfirmedSince: TimeInterval?
  private var reportedUnconfirmed = false
  private var unconfirmed: (@Sendable () -> Void)?

  init(
    post: @escaping Post = AutoPresser.postKey, focus: @escaping FocusCheck = AutoPresser.focus
  ) {
    self.post = post
    self.focus = focus
  }

  deinit { stop() }

  /// Called on the press queue, once per `start`, when presses have been withheld for
  /// `unconfirmedDelay` because focus couldn't be confirmed. Otherwise that would look like
  /// auto-press being on and doing nothing.
  func onUnconfirmed(_ handler: @escaping @Sendable () -> Void) {
    lock.withLock { unconfirmed = handler }
  }

  func start(_ settings: AutoPressSettings) {
    let wanted = Configuration(
      keyCode: settings.pressedKeyCode, interval: settings.pressInterval,
      hold: settings.holdDuration, bundleID: settings.target.bundleID)
    lock.withLock {
      guard timer == nil || wanted != configuration else { return }
      stopLocked()
      configuration = wanted
      let generation = generation
      let timer = DispatchSource.makeTimerSource(queue: queue)
      timer.schedule(deadline: .now(), repeating: wanted.interval, leeway: .milliseconds(5))
      timer.setEventHandler { [weak self] in self?.press(wanted, generation: generation) }
      timer.resume()
      self.timer = timer
    }
  }

  /// Releases a held key at once. No press is posted after this returns.
  func stop() {
    lock.withLock { stopLocked() }
  }

  private func stopLocked() {
    timer?.cancel()
    timer = nil
    configuration = nil
    generation += 1
    unconfirmedSince = nil
    reportedUnconfirmed = false
    releaseLocked()
  }

  /// Posts the held key's key-up now rather than when it's due.
  private func releaseLocked() {
    guard let held else { return }
    post(held.keyCode, false)
    self.held = nil
  }

  private func press(_ configuration: Configuration, generation: Int) {
    // Asked at press time, outside the lock so a slow answer can't hold up `stop`.
    let focus = focus(configuration.bundleID)
    let report: (@Sendable () -> Void)? = lock.withLock {
      guard generation == self.generation else { return nil }
      guard focus == .target else {
        return focus == .unconfirmed ? unconfirmedLocked() : clearUnconfirmedLocked()
      }
      unconfirmedSince = nil
      releaseLocked()
      post(configuration.keyCode, true)
      presses += 1
      let press = presses
      held = (configuration.keyCode, press)
      releases.asyncAfter(deadline: .now() + configuration.hold) { [weak self] in
        guard let self else { return }
        lock.withLock {
          guard held?.press == press else { return }
          releaseLocked()
        }
      }
      return nil
    }
    report?()
  }

  private func clearUnconfirmedLocked() -> (@Sendable () -> Void)? {
    unconfirmedSince = nil
    return nil
  }

  /// The handler to call, once focus has stayed unconfirmed long enough to be worth reporting.
  private func unconfirmedLocked() -> (@Sendable () -> Void)? {
    let now = ProcessInfo.processInfo.systemUptime
    let since = unconfirmedSince ?? now
    unconfirmedSince = since
    guard !reportedUnconfirmed, now - since >= Self.unconfirmedDelay else { return nil }
    reportedUnconfirmed = true
    return unconfirmed
  }

  /// Used only under `lock`, through `post`.
  nonisolated(unsafe) private static let eventSource = CGEventSource(stateID: .hidSystemState)

  @Sendable static func postKey(_ keyCode: CGKeyCode, down: Bool) {
    guard let event = CGEvent(keyboardEventSource: eventSource, virtualKey: keyCode, keyDown: down)
    else { return }
    // Clear flags so modifiers held for the toggle shortcut don't turn this into a combination.
    event.flags = []
    event.post(tap: .cghidEventTap)
  }

  /// Asks the Accessibility server which app has keyboard focus, and also requires
  /// `NSWorkspace` to agree, as the press check always did. Off the main thread `NSWorkspace`
  /// only catches up when the main run loop turns, so on its own it could still name the target
  /// for as long as the main thread is busy after a switch away. Fails closed.
  @Sendable static func focus(_ bundleID: String) -> Focus {
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID else {
      return .other
    }
    let system = AXUIElementCreateSystemWide()
    // The answer normally takes microseconds. A slow one must not stall the presses behind it
    // for the default timeout of several seconds.
    AXUIElementSetMessagingTimeout(system, 0.25)
    var focused: CFTypeRef?
    guard
      AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &focused)
        == .success,
      let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
    else { return .unconfirmed }
    var pid: pid_t = 0
    guard AXUIElementGetPid(focused as! AXUIElement, &pid) == .success else { return .unconfirmed }
    return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleID
      ? .target : .other
  }
}
