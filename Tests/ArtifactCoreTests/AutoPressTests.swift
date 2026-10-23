import ArtifactCore
import Foundation
import Testing

private let start = Date(timeIntervalSince1970: 1_000)

@Test func autoPressDefaultsPressFInGeForceNowAndToggleWithBacktick() {
  let settings = AutoPressSettings()
  #expect(settings.target == .geforceNow)
  #expect(settings.pressedKeyCode == 3)
  #expect(settings.trigger == .key(keyCode: 50, modifiers: []))
  #expect(settings.pressesPerSecond == 8)
  #expect(settings.autoOffEnabled)
  #expect(settings.autoOffMinutes == 10)
  #expect(settings.holdDuration == 0.04)
}

@Test func autoPressSettingsClampRatesAndTimers() {
  var settings = AutoPressSettings()
  settings.pressesPerSecond = 0
  #expect(settings.pressesPerSecond == 1)
  settings.pressesPerSecond = 50
  #expect(settings.pressesPerSecond == 20)
  #expect(settings.holdDuration == 0.025)
  settings.autoOffMinutes = -3
  #expect(settings.autoOffMinutes == 1)
  settings.autoOffMinutes = 10_000
  #expect(settings.autoOffMinutes == 720)
}

@Test func autoPressSettingsRoundTripAndTolerateDamagedStorage() throws {
  var settings = AutoPressSettings()
  settings.target = AutoPressTarget(bundleID: "com.example.game", name: "Game")
  settings.pressedKeyCode = 49
  settings.trigger = .mouse(button: 3)
  settings.pressesPerSecond = 12
  settings.autoOffEnabled = false
  settings.autoOffMinutes = 30
  let data = try JSONEncoder().encode(settings)
  #expect(AutoPressSettings.decode(data) == settings)

  #expect(AutoPressSettings.decode(nil) == AutoPressSettings())
  #expect(AutoPressSettings.decode(Data("not json".utf8)) == AutoPressSettings())
  let partial = AutoPressSettings.decode(
    Data(#"{"pressesPerSecond": 99, "autoOffMinutes": 0, "trigger": "bad"}"#.utf8))
  #expect(partial.pressesPerSecond == 20)
  #expect(partial.autoOffMinutes == 1)
  #expect(partial.trigger == .default)
}

@Test func autoPressTriggerCannotBeTheBarePressedKey() {
  let bare = AutoPressTrigger.key(keyCode: 3, modifiers: [])
  #expect(bare.conflicts(withPressedKey: 3))
  #expect(!AutoPressTrigger.key(keyCode: 3, modifiers: .option).conflicts(withPressedKey: 3))
  #expect(!AutoPressTrigger.mouse(button: 3).conflicts(withPressedKey: 3))
  let stored = AutoPressSettings.decode(
    Data(#"{"pressedKeyCode": 3, "trigger": {"key": {"keyCode": 3, "modifiers": 0}}}"#.utf8))
  #expect(!stored.trigger.conflicts(withPressedKey: stored.pressedKeyCode))
}

@Test func autoPressSessionPressesOnlyWhileOnFrontmostAndBeforeTimer() {
  var settings = AutoPressSettings()
  var session = AutoPressSession()
  #expect(!session.shouldPress(targetFrontmost: true, at: start, settings))
  #expect(session.status(targetFrontmost: true, at: start, settings, keyName: "F") == "Off")

  session.turnOn(at: start)
  #expect(session.isOn)
  #expect(session.shouldPress(targetFrontmost: true, at: start, settings))
  #expect(!session.shouldPress(targetFrontmost: false, at: start, settings))
  #expect(session.autoOffDate(settings) == start.addingTimeInterval(600))
  #expect(
    session.status(targetFrontmost: true, at: start.addingTimeInterval(61), settings, keyName: "F")
      == "Pressing F · off in 9 min")
  #expect(
    session.status(targetFrontmost: false, at: start, settings, keyName: "F")
      == "On, paused until NVIDIA GeForce NOW is in front · off in 10 min")
  #expect(!session.isExpired(at: start.addingTimeInterval(599), settings))
  #expect(session.isExpired(at: start.addingTimeInterval(600), settings))
  #expect(!session.shouldPress(targetFrontmost: true, at: start.addingTimeInterval(600), settings))

  settings.autoOffEnabled = false
  #expect(session.autoOffDate(settings) == nil)
  #expect(
    session.shouldPress(targetFrontmost: true, at: start.addingTimeInterval(86_400), settings))
  #expect(session.status(targetFrontmost: true, at: start, settings, keyName: "F") == "Pressing F")

  session.turnOff()
  #expect(!session.isOn)
  #expect(session.startedAt == nil)
}
