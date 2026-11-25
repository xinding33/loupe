import CoreGraphics
import Foundation
import LoupeCore
import Testing

@testable import Loupe

/// Stands in for event posting and the focus check, so these tests never send input. Waits are
/// on what the presser did, with generous timeouts, so a slow machine can't fail them.
private final class FakeKeyboard: @unchecked Sendable {
  struct Event {
    let time: TimeInterval
    let keyCode: CGKeyCode
    let down: Bool
  }
  private let lock = NSLock()
  private var recorded: [Event] = []
  private var focus = AutoPresser.Focus.target
  private var checkDelay: TimeInterval = 0
  private var asked: Set<String> = []
  /// Signalled on each key-down.
  let pressed = DispatchSemaphore(value: 0)
  /// Signalled on each focus check, once it has answered.
  let checked = DispatchSemaphore(value: 0)
  /// Signalled when the presser reports that focus stayed unconfirmed.
  let reported = DispatchSemaphore(value: 0)

  var events: [Event] { lock.withLock { recorded } }
  /// The bundle identifiers the presser asked about.
  var askedFor: Set<String> { lock.withLock { asked } }
  var downs: [Event] { events.filter(\.down) }
  func setFocus(_ value: AutoPresser.Focus) { lock.withLock { focus = value } }
  /// Makes every focus check take this long, as a slow Accessibility answer would.
  func setCheckDelay(_ value: TimeInterval) { lock.withLock { checkDelay = value } }

  func presser() -> AutoPresser {
    let presser = AutoPresser(
      post: { [self] keyCode, down in
        lock.withLock {
          recorded.append(
            Event(time: ProcessInfo.processInfo.systemUptime, keyCode: keyCode, down: down))
        }
        if down { pressed.signal() }
      },
      focus: { [self] bundleID in
        let delay = lock.withLock { checkDelay }
        if delay > 0 { Thread.sleep(forTimeInterval: delay) }
        let answer = lock.withLock {
          asked.insert(bundleID)
          return focus
        }
        checked.signal()
        return answer
      })
    presser.onUnconfirmed { [self] in reported.signal() }
    return presser
  }

  /// Waits for this many more focus checks to answer.
  func waitForChecks(_ count: Int) -> Bool {
    (0..<count).allSatisfy { _ in checked.wait(timeout: .now() + 5) == .success }
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
@Test func autoPressKeepsPressingWhileTheMainThreadIsBusy() throws {
  let keyboard = FakeKeyboard()
  let presser = keyboard.presser()
  presser.start(settings(pressesPerSecond: 20))
  // Each wait blocks the main thread. A presser on the main queue would never get to press.
  for _ in 0..<4 { #expect(keyboard.pressed.wait(timeout: .now() + 5) == .success) }
  presser.stop()
  #expect(keyboard.downs.count >= 4)
  #expect(keyboard.isBalanced)
  #expect(keyboard.askedFor == ["invalid.loupe.tests"])
}

@Test func autoPressStopReleasesTheHeldKeyAndPressesNothingAfter() throws {
  let keyboard = FakeKeyboard()
  let presser = keyboard.presser()
  presser.start(settings(pressesPerSecond: 1))
  #expect(keyboard.pressed.wait(timeout: .now() + 5) == .success)
  presser.stop()
  let events = keyboard.events
  #expect(events.map(\.down) == [true, false])
  #expect(events.map(\.keyCode) == [3, 3])

  presser.start(settings(pressesPerSecond: 20))
  for _ in 0..<3 { _ = keyboard.pressed.wait(timeout: .now() + 5) }
  presser.stop()
  let stopped = keyboard.events.count
  #expect(keyboard.isBalanced)
  Thread.sleep(forTimeInterval: 0.2)
  #expect(keyboard.events.count == stopped)
}

@Test func autoPressPostsNothingWhileTheTargetIsNotInFront() throws {
  let keyboard = FakeKeyboard()
  keyboard.setFocus(.other)
  let presser = keyboard.presser()
  presser.start(settings(pressesPerSecond: 20))
  #expect(keyboard.waitForChecks(3))
  #expect(keyboard.events.isEmpty)
  #expect(keyboard.askedFor == ["invalid.loupe.tests"])

  // Once the target leaves the front, the press under way may land; none follows it.
  keyboard.setFocus(.target)
  #expect(keyboard.pressed.wait(timeout: .now() + 5) == .success)
  keyboard.setFocus(.other)
  #expect(keyboard.waitForChecks(2))
  let afterSwitch = keyboard.downs.count
  #expect(keyboard.waitForChecks(3))
  #expect(keyboard.downs.count == afterSwitch)
  presser.stop()
  #expect(keyboard.isBalanced)
}

@Test func autoPressReleasesOnTimeWhileTheNextFocusCheckIsSlow() throws {
  let keyboard = FakeKeyboard()
  keyboard.setCheckDelay(0.5)
  let presser = keyboard.presser()
  // At 20 a second the key is held for 25 ms, and each press's check takes half a second.
  presser.start(settings(pressesPerSecond: 20))
  #expect(keyboard.pressed.wait(timeout: .now() + 5) == .success)
  #expect(keyboard.pressed.wait(timeout: .now() + 5) == .success)
  presser.stop()
  let events = keyboard.events
  let firstUp = try #require(events.first { !$0.down })
  // Sharing a queue with the checks would hold the key for the whole half second.
  #expect(firstUp.time - events[0].time < 0.3)
  #expect(keyboard.isBalanced)
}

@Test func autoPressReportsFocusItCannotConfirmOnceAndPressesNothing() throws {
  let keyboard = FakeKeyboard()
  keyboard.setFocus(.unconfirmed)
  let presser = keyboard.presser()
  presser.start(settings(pressesPerSecond: 20))
  #expect(keyboard.reported.wait(timeout: .now() + 5) == .success)
  // Not again for the same run of presses.
  #expect(keyboard.waitForChecks(5))
  #expect(keyboard.reported.wait(timeout: .now()) == .timedOut)
  #expect(keyboard.events.isEmpty)
  presser.stop()
}
