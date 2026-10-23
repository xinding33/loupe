import AppKit
import ArtifactCore

/// Repeatedly presses a key, but only while the target app is frontmost.
@MainActor
final class AutoPresser {
  private struct Configuration: Equatable {
    let keyCode: CGKeyCode
    let interval: TimeInterval
    let hold: TimeInterval
    let bundleID: String
  }

  private let eventSource = CGEventSource(stateID: .hidSystemState)
  private var timer: DispatchSourceTimer?
  private var configuration: Configuration?
  /// The key-up for a press still being held, and the work that posts it.
  private var pendingUp: (event: CGEvent, work: DispatchWorkItem)?

  func start(_ settings: AutoPressSettings) {
    let wanted = Configuration(
      keyCode: settings.pressedKeyCode, interval: settings.pressInterval,
      hold: settings.holdDuration, bundleID: settings.target.bundleID)
    guard timer == nil || wanted != configuration else { return }
    stop()
    configuration = wanted

    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now(), repeating: wanted.interval, leeway: .milliseconds(5))
    timer.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.press() } }
    timer.resume()
    self.timer = timer
  }

  func stop() {
    timer?.cancel()
    timer = nil
    releaseKey()
  }

  /// Posts the pending key-up now rather than when it's due.
  private func releaseKey() {
    guard let pendingUp else { return }
    pendingUp.work.cancel()
    pendingUp.event.post(tap: .cghidEventTap)
    self.pendingUp = nil
  }

  private func press() {
    // The app-activation notification can lag a tick behind the actual switch.
    guard let configuration,
      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == configuration.bundleID,
      let down = CGEvent(
        keyboardEventSource: eventSource, virtualKey: configuration.keyCode, keyDown: true),
      let up = CGEvent(
        keyboardEventSource: eventSource, virtualKey: configuration.keyCode, keyDown: false)
    else { return }

    // Clear flags so modifiers held for the toggle shortcut don't turn this into a combination.
    down.flags = []
    up.flags = []
    releaseKey()
    down.post(tap: .cghidEventTap)
    let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.releaseKey() } }
    pendingUp = (up, work)
    DispatchQueue.main.asyncAfter(deadline: .now() + configuration.hold, execute: work)
  }
}
