import Foundation
import LoupeCore
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

private let started = ProcessStart(seconds: 1_700_000_000, microseconds: 250_000)
private let game = AutoPressTarget(pid: 4321, start: started, name: "wine64-preloader")

/// A candidate's start time, failing the test if matching reads it when it shouldn't.
private func never() -> ProcessStart? {
  Issue.record("Read the start time of a process that couldn't match")
  return nil
}

@Test func autoPressTargetWithABundleIdentifierMatchesOnlyThatIdentifier() {
  let target = AutoPressTarget.geforceNow
  #expect(target.matches(bundleID: "com.nvidia.gfnpc.mall", pid: 12, start: never))
  #expect(!target.matches(bundleID: "com.example.other", pid: 12, start: never))
  #expect(!target.matches(bundleID: nil, pid: 12, start: never))
  #expect(!target.matches(bundleID: "", pid: 12, start: never))
  #expect(target.confirms(focusedPID: 12, frontPID: 12, start: never) { "com.nvidia.gfnpc.mall" })
  #expect(target.confirms(focusedPID: 13, frontPID: 12, start: never) { "com.nvidia.gfnpc.mall" })
  #expect(!target.confirms(focusedPID: 12, frontPID: 12, start: never) { nil })
  #expect(!target.confirms(focusedPID: 12, frontPID: 12, start: never) { "com.example.other" })
  #expect(!target.isInstance)
}

@Test func autoPressInstanceTargetMatchesOnlyItsOwnRun() {
  #expect(game.matches(bundleID: nil, pid: 4321) { started })
  // The pid reused by a later process.
  #expect(
    !game.matches(bundleID: nil, pid: 4321) {
      ProcessStart(seconds: started.seconds, microseconds: started.microseconds + 1)
    })
  #expect(
    !game.matches(bundleID: nil, pid: 4321) {
      ProcessStart(seconds: started.seconds + 1, microseconds: started.microseconds)
    })
  #expect(!game.matches(bundleID: nil, pid: 4321) { nil })
  #expect(!game.matches(bundleID: nil, pid: 4322, start: never))
  #expect(!game.matches(bundleID: "com.example.game", pid: 4321, start: never))
  #expect(!game.matches(bundleID: "", pid: 4321, start: never))

  // Confirmed by pid and start time again, without looking up the focused app's bundle.
  let unread: () -> String? = {
    Issue.record("Looked up the focused app of an instance target")
    return nil
  }
  #expect(
    game.confirms(
      focusedPID: 4321, frontPID: 4321, start: { started }, focusedBundleID: unread))
  // The game quit and its pid went to another process while Accessibility was answering.
  #expect(
    !game.confirms(
      focusedPID: 4321, frontPID: 4321,
      start: { ProcessStart(seconds: started.seconds, microseconds: started.microseconds + 1) },
      focusedBundleID: unread))
  #expect(
    !game.confirms(focusedPID: 4321, frontPID: 4321, start: { nil }, focusedBundleID: unread))
  #expect(
    !game.confirms(focusedPID: 999, frontPID: 4321, start: never, focusedBundleID: unread))
  #expect(
    !game.confirms(focusedPID: 4321, frontPID: 999, start: never, focusedBundleID: unread))
}

@Test func autoPressTargetWithEmptyOrMissingIdentityMatchesNothing() throws {
  let empty = AutoPressTarget(bundleID: "", name: "Empty")
  #expect(!empty.matches(bundleID: "", pid: 1, start: never))
  #expect(!empty.matches(bundleID: nil, pid: 1, start: never))
  #expect(!empty.confirms(focusedPID: 1, frontPID: 1, start: never) { "" })
  for stored in [
    #"{"name": "X"}"#, #"{"pid": 4321, "name": "X"}"#,
    #"{"pid": 4321, "startSeconds": 1700000000, "name": "X"}"#,
    #"{"pid": 0, "startSeconds": 1, "startMicroseconds": 0, "name": "X"}"#,
  ] {
    let target = try JSONDecoder().decode(AutoPressTarget.self, from: Data(stored.utf8))
    #expect(target.bundleID == nil)
    for pid: Int32 in [0, 4321] {
      #expect(
        !target.matches(bundleID: nil, pid: pid) { ProcessStart(seconds: 1, microseconds: 0) })
      #expect(!target.matches(bundleID: nil, pid: pid) { started })
      #expect(
        !target.confirms(
          focusedPID: pid, frontPID: pid, start: { started }, focusedBundleID: { nil }))
    }
  }
  #expect(
    !AutoPressTarget(pid: 0, start: started, name: "X").matches(bundleID: nil, pid: 0) {
      started
    })
}

@Test func autoPressTargetFromARunningProcessPrefersItsBundleIdentifier() {
  #expect(
    AutoPressTarget(bundleID: "com.example.game", pid: 9, start: never, name: "G")
      == AutoPressTarget(bundleID: "com.example.game", name: "G"))
  #expect(
    AutoPressTarget(bundleID: nil, pid: 4321, start: { started }, name: "wine64-preloader")
      == game)
  #expect(AutoPressTarget(bundleID: nil, pid: 4321, start: { nil }, name: "G") == nil)
  #expect(AutoPressTarget(bundleID: nil, pid: 0, start: never, name: "G") == nil)
  #expect(AutoPressTarget(bundleID: nil, pid: -1, start: never, name: "G") == nil)
  #expect(AutoPressTarget(bundleID: "", pid: 4321, start: never, name: "G") == nil)
}

@Test func autoPressSettingsStoredByReleasedVersionsDecodeToTheSameTarget() throws {
  let stored = Data(
    #"{"target": {"bundleID": "com.example.game", "name": "Game"}, "pressedKeyCode": 49}"#.utf8)
  let settings = AutoPressSettings.decode(stored)
  #expect(settings.target == AutoPressTarget(bundleID: "com.example.game", name: "Game"))
  #expect(settings.target.pid == nil && settings.target.start == nil)
  #expect(settings.pressedKeyCode == 49)

  // A bundle target is still written in the old shape, so a released version reads it back.
  let encoded = try JSONEncoder().encode(AutoPressTarget.geforceNow)
  let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: String])
  #expect(object == ["bundleID": "com.nvidia.gfnpc.mall", "name": "NVIDIA GeForce NOW"])
}

@Test func autoPressSettingsRoundTripAnInstanceTarget() throws {
  var settings = AutoPressSettings()
  settings.target = game
  let data = try JSONEncoder().encode(settings)
  let decoded = AutoPressSettings.decode(data)
  #expect(decoded == settings)
  #expect(decoded.target.matches(bundleID: nil, pid: 4321) { started })
  let object = try #require(
    JSONSerialization.jsonObject(with: JSONEncoder().encode(game)) as? [String: Any])
  #expect(Set(object.keys) == ["pid", "startSeconds", "startMicroseconds", "name"])
}

@Test func autoPressChoicesKeepThePresetFirstAndListEachRunningTargetOnce() {
  let launcher = AutoPressTarget(
    pid: 4000, start: ProcessStart(seconds: 1_700_000_000, microseconds: 1),
    name: "wine64-preloader")
  let running = [
    AutoPressTarget(bundleID: "com.example.zed", name: "Zed"),
    game,
    AutoPressTarget(bundleID: "com.nvidia.gfnpc.mall", name: "GeForce NOW"),
    AutoPressTarget(bundleID: "com.example.arc", name: "arc"),
    AutoPressTarget(bundleID: "com.example.zed", name: "Zed"),
    launcher,
    AutoPressTarget(pid: 4321, start: started, name: "wine64-preloader"),
  ]
  let choices = AutoPressTarget.choices(current: .geforceNow, running: running)
  #expect(
    AutoPressTarget.titles(choices) == [
      "NVIDIA GeForce NOW", "arc", "wine64-preloader (4000)", "wine64-preloader (4321)", "Zed",
    ])
  // The same run under another name is still one entry.
  let renamed = AutoPressTarget(pid: 4321, start: started, name: "Renamed")
  #expect(AutoPressTarget.choices(current: game, running: [renamed]) == [.geforceNow, game])
  #expect(AutoPressTarget.choices(current: .geforceNow, running: []) == [.geforceNow])
  #expect(
    AutoPressTarget.titles([.geforceNow, game]) == ["NVIDIA GeForce NOW", "wine64-preloader"])
  // Only the bare entries take a pid when an app shares the name.
  let app = AutoPressTarget(bundleID: "com.example.wine", name: "wine64-preloader")
  #expect(
    AutoPressTarget.titles([app, game]) == ["wine64-preloader", "wine64-preloader (4321)"])

  let gone = AutoPressTarget(bundleID: "com.example.gone", name: "Gone")
  #expect(AutoPressTarget.choices(current: gone, running: [game]) == [.geforceNow, gone, game])
  #expect(AutoPressTarget.choices(current: game, running: [game]) == [.geforceNow, game])
  let damaged = AutoPressTarget(bundleID: "", name: "Damaged")
  #expect(AutoPressTarget.choices(current: damaged, running: []) == [.geforceNow])
  var partial = game
  partial.startMicroseconds = nil
  #expect(AutoPressTarget.choices(current: partial, running: []) == [.geforceNow])
}

@Test func autoPressExplainsAnInstanceTargetAndStopsWaitingOnceItQuits() {
  #expect(AutoPressTarget.geforceNow.instanceNote(running: false) == nil)
  #expect(
    game.instanceNote(running: true)
      == "Picked for this run only. Choose it again each time the game starts.")
  #expect(
    game.instanceNote(running: false)
      == "wine64-preloader has quit. Choose it again once the game is open.")

  var settings = AutoPressSettings()
  settings.target = game
  var session = AutoPressSession()
  session.turnOn(at: start)
  #expect(
    session.status(targetFrontmost: false, targetRunning: true, at: start, settings, keyName: "F")
      == "On, paused until wine64-preloader is in front · off in 10 min")
  #expect(
    session.status(targetFrontmost: false, targetRunning: false, at: start, settings, keyName: "F")
      == "On, but wine64-preloader has quit · off in 10 min")
  // The frontmost flag can be stale just after the game quits; having quit wins.
  #expect(
    session.status(targetFrontmost: true, targetRunning: false, at: start, settings, keyName: "F")
      == "On, but wine64-preloader has quit · off in 10 min")
  // An app can always be opened again, so it's still waited for.
  settings.target = .geforceNow
  #expect(
    session.status(targetFrontmost: false, targetRunning: false, at: start, settings, keyName: "F")
      == "On, paused until NVIDIA GeForce NOW is in front · off in 10 min")
}
