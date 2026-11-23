import CoreGraphics
import Foundation
import LoupeCore
import Testing

@testable import Loupe

/// Stands in for event posting, so these tests never send input.
private final class FakeKeyboard: @unchecked Sendable {
  struct Event {
    let time: TimeInterval
    let keyCode: CGKeyCode
    let down: Bool
  }
  private let lock = NSLock()
  private var recorded: [Event] = []
  private var frontmost = true
  private var asked: Set<String> = []
  /// Signalled on each key-down.
  let pressed = DispatchSemaphore(value: 0)

  var events: [Event] { lock.withLock { recorded } }
  /// The bundle identifiers the presser asked about.
  var askedFor: Set<String> { lock.withLock { asked } }
  var downs: [Event] { events.filter(\.down) }
  func setFrontmost(_ value: Bool) { lock.withLock { frontmost = value } }

  func presser() -> AutoPresser {
    AutoPresser(
      post: { [self] keyCode, down in
        lock.withLock {
          recorded.append(
            Event(time: ProcessInfo.processInfo.systemUptime, keyCode: keyCode, down: down))
        }
        if down { pressed.signal() }
      },
      isFrontmost: { [self] bundleID in
        lock.withLock {
          asked.insert(bundleID)
          return frontmost
        }
      })
  }

  /// Every key-down is followed by its key-up, and no key is left down.
  var isBalanced: Bool {
    let events = events
    return events.count.isMultiple(of: 2)
      && events.indices.allSatisfy { events[$0].down == $0.isMultiple(of: 2) }
  }
}

private func settings(pressesPerSecond: Int) -> AutoPressSettings {
  var settings = AutoPressSettings()
  settings.target = AutoPressTarget(bundleID: "invalid.loupe.tests", name: "Test target")
  settings.pressesPerSecond = pressesPerSecond
  return settings
}

@MainActor
@Test func autoPressKeepsItsCadenceWhileTheMainThreadIsBusy() throws {
  let keyboard = FakeKeyboard()
  let presser = keyboard.presser()
  presser.start(settings(pressesPerSecond: 20))
  #expect(keyboard.pressed.wait(timeout: .now() + 1) == .success)
  let start = ProcessInfo.processInfo.systemUptime
  Thread.sleep(forTimeInterval: 0.3)
  let end = ProcessInfo.processInfo.systemUptime
  presser.stop()
  let times = keyboard.downs.map(\.time).filter { $0 >= start && $0 <= end }
  // Six presses are due in 300 ms at 20 a second; on the main queue there would be none. The
  // bound is loose so a slow CI machine can't fail it.
  #expect(times.count >= 3)
  #expect(keyboard.isBalanced)
  #expect(keyboard.askedFor == ["invalid.loupe.tests"])
}

@Test func autoPressStopReleasesTheHeldKeyAndPressesNothingAfter() throws {
  let keyboard = FakeKeyboard()
  let presser = keyboard.presser()
  // One press a second holds the key for 40 ms.
  presser.start(settings(pressesPerSecond: 1))
  #expect(keyboard.pressed.wait(timeout: .now() + 1) == .success)
  presser.stop()
  let events = keyboard.events
  #expect(events.map(\.down) == [true, false])
  #expect(events.map(\.keyCode) == [3, 3])

  presser.start(settings(pressesPerSecond: 20))
  for _ in 0..<3 { _ = keyboard.pressed.wait(timeout: .now() + 1) }
  presser.stop()
  let stopped = keyboard.events.count
  #expect(keyboard.isBalanced)
  Thread.sleep(forTimeInterval: 0.2)
  #expect(keyboard.events.count == stopped)
}

@Test func autoPressPostsNothingWhileTheTargetIsNotInFront() throws {
  let keyboard = FakeKeyboard()
  keyboard.setFrontmost(false)
  let presser = keyboard.presser()
  presser.start(settings(pressesPerSecond: 20))
  Thread.sleep(forTimeInterval: 0.2)
  #expect(keyboard.events.isEmpty)
  #expect(keyboard.askedFor == ["invalid.loupe.tests"])

  // Pressing stops on the next press once the target leaves the front.
  keyboard.setFrontmost(true)
  #expect(keyboard.pressed.wait(timeout: .now() + 1) == .success)
  keyboard.setFrontmost(false)
  Thread.sleep(forTimeInterval: 0.1)
  let afterSwitch = keyboard.events.count
  Thread.sleep(forTimeInterval: 0.2)
  #expect(keyboard.events.count == afterSwitch)
  #expect(keyboard.isBalanced)
  presser.stop()
}
