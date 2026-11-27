import Foundation

/// Modifier keys held with a toggle shortcut, independent of AppKit and Carbon.
public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: UInt8
  public init(rawValue: UInt8) { self.rawValue = rawValue }
  public static let command = KeyModifiers(rawValue: 1 << 0)
  public static let option = KeyModifiers(rawValue: 1 << 1)
  public static let control = KeyModifiers(rawValue: 1 << 2)
  public static let shift = KeyModifiers(rawValue: 1 << 3)
}

/// What turns auto-pressing on and off while the target app is in front.
public enum AutoPressTrigger: Codable, Hashable, Sendable {
  /// `keyCode` is a macOS virtual key code.
  case key(keyCode: UInt16, modifiers: KeyModifiers)
  /// `NSEvent.buttonNumber` numbering: 2 is middle, 3 and 4 are the side buttons.
  case mouse(button: Int)

  /// Backtick with no modifiers. It is registered only while the target app is in front.
  public static let `default` = AutoPressTrigger.key(keyCode: 50, modifiers: [])

  /// The pressed key with no modifiers would retrigger itself on every synthetic press.
  public func conflicts(withPressedKey keyCode: UInt16) -> Bool {
    self == .key(keyCode: keyCode, modifiers: [])
  }
}

/// When a process started, as the kernel reports it. With the pid it tells one run of a program
/// from a later process that reuses the pid.
public struct ProcessStart: Hashable, Sendable {
  public var seconds: UInt64
  public var microseconds: UInt64
  public init(seconds: UInt64, microseconds: UInt64) {
    self.seconds = seconds
    self.microseconds = microseconds
  }
}

/// The app auto-press sends keys to: GeForce NOW to start with.
///
/// An app is identified by its bundle identifier. A process with none, such as a game running
/// under Wine, is identified as the one running instance the user picked, by its pid and start
/// time. Nothing about it is inferred, so it matches only that run, and the user picks the game
/// again each time it starts.
///
/// Stored as `bundleID` and `name`, or `pid`, `startSeconds`, `startMicroseconds` and `name`.
/// Values saved by released versions have only `bundleID` and `name`, and still decode.
public struct AutoPressTarget: Codable, Hashable, Sendable {
  public var bundleID: String?
  public var pid: Int32?
  public var startSeconds: UInt64?
  public var startMicroseconds: UInt64?
  /// For display only. It never decides a match.
  public var name: String

  public init(bundleID: String, name: String) {
    self.bundleID = bundleID
    self.name = name
  }

  /// One running instance of a process that has no bundle identifier.
  public init(pid: Int32, start: ProcessStart, name: String) {
    self.pid = pid
    startSeconds = start.seconds
    startMicroseconds = start.microseconds
    self.name = name
  }

  /// A running process as a target: by bundle identifier when it has one, else as this instance.
  /// Nil when it has neither, as when its start time can't be read, since such a target could
  /// never match. `start` is read only for a process without a bundle identifier.
  public init?(bundleID: String?, pid: Int32, start: () -> ProcessStart?, name: String) {
    if let bundleID {
      guard !bundleID.isEmpty else { return nil }
      self.init(bundleID: bundleID, name: name)
    } else if pid > 0, let start = start() {
      self.init(pid: pid, start: start, name: name)
    } else {
      return nil
    }
  }

  public static let geforceNow = AutoPressTarget(
    bundleID: "com.nvidia.gfnpc.mall", name: "NVIDIA GeForce NOW")

  /// Whether this is one running instance rather than an app, though maybe a damaged one.
  public var isInstance: Bool { bundleID == nil }

  /// The start time of an instance target, nil for an app or a damaged value.
  public var start: ProcessStart? {
    guard let startSeconds, let startMicroseconds else { return nil }
    return ProcessStart(seconds: startSeconds, microseconds: startMicroseconds)
  }

  /// Whether a process is the target. A target with a bundle identifier matches on that alone.
  /// An instance matches only a process with no bundle identifier, its pid and its start time;
  /// `start` is read only once the pid agrees, and a start time that can't be read never
  /// matches. Empty or missing values never match, so a damaged target presses nothing.
  public func matches(
    bundleID candidateBundleID: String?, pid candidatePID: Int32, start: () -> ProcessStart?
  ) -> Bool {
    if let bundleID {
      return !bundleID.isEmpty && candidateBundleID == bundleID
    }
    guard let pid, pid > 0, let own = self.start, candidateBundleID == nil, candidatePID == pid
    else { return false }
    return start() == own
  }

  /// The check against the app Accessibility says has keyboard focus, made after `matches`
  /// passed for the frontmost app, `frontPID`. An app is checked by bundle identifier again. An
  /// instance is checked by pid and then by start time once more: the game could have quit and
  /// its pid gone to another process while Accessibility was answering. `start` is read only
  /// once the pids agree.
  public func confirms(
    focusedPID: Int32, frontPID: Int32, start: () -> ProcessStart?,
    focusedBundleID: () -> String?
  ) -> Bool {
    if let bundleID {
      return !bundleID.isEmpty && focusedBundleID() == bundleID
    }
    guard let pid, pid > 0, let own = self.start, focusedPID == pid, frontPID == pid else {
      return false
    }
    return start() == own
  }

  /// Two targets that match the same processes, whatever they're called.
  public func sameIdentity(as other: AutoPressTarget) -> Bool {
    guard bundleID == other.bundleID else { return false }
    return bundleID != nil || (pid == other.pid && start == other.start)
  }

  /// The targets a chooser offers: `preset` first, then `current` unless it's the preset, then
  /// the running processes sorted by name, then pid. A process matching a target already listed
  /// is left out.
  public static func choices(
    preset: AutoPressTarget = .geforceNow, current: AutoPressTarget, running: [AutoPressTarget]
  ) -> [AutoPressTarget] {
    var listed = [preset]
    let sorted = running.sorted {
      let order = $0.name.localizedStandardCompare($1.name)
      return order == .orderedSame ? ($0.pid ?? 0) < ($1.pid ?? 0) : order == .orderedAscending
    }
    for target in [current] + sorted
    where target.hasIdentity && !listed.contains(where: target.sameIdentity) {
      listed.append(target)
    }
    return listed
  }

  /// Menu titles for `choices`: each name, with the pid after an instance's name when another
  /// entry shows the same name, so two runs of one program can be told apart.
  public static func titles(_ choices: [AutoPressTarget]) -> [String] {
    choices.map { target in
      let shared = choices.contains { $0 != target && $0.name == target.name }
      guard shared, target.isInstance, let pid = target.pid else { return target.name }
      return "\(target.name) (\(pid))"
    }
  }

  /// A note for the panel about an instance target, nil for an app. `running` is whether that
  /// instance is still running.
  public func instanceNote(running: Bool) -> String? {
    guard isInstance else { return nil }
    return running
      ? "Picked for this run only. Choose it again each time the game starts."
      : "\(name) has quit. Choose it again once the game is open."
  }

  private var hasIdentity: Bool {
    if let bundleID { return !bundleID.isEmpty }
    return (pid ?? 0) > 0 && start != nil
  }
}

public struct AutoPressSettings: Codable, Equatable, Sendable {
  public static let pressesPerSecondRange = 1...20
  public static let autoOffMinutesRange = 1...720
  /// F, which talks, picks up and skips dialogue in Genshin Impact.
  public static let defaultPressedKey: UInt16 = 3

  public var target = AutoPressTarget.geforceNow
  public var pressedKeyCode = defaultPressedKey
  public var trigger = AutoPressTrigger.default
  public var pressesPerSecond = 8 {
    didSet { pressesPerSecond = Self.clamp(pressesPerSecond, to: Self.pressesPerSecondRange) }
  }
  public var autoOffEnabled = true
  public var autoOffMinutes = 10 {
    didSet { autoOffMinutes = Self.clamp(autoOffMinutes, to: Self.autoOffMinutesRange) }
  }

  public init() {}

  /// Tolerates missing and out-of-range fields so a stored value never blocks launch.
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let defaults = AutoPressSettings()
    target = (try? values.decodeIfPresent(AutoPressTarget.self, forKey: .target)) ?? defaults.target
    pressedKeyCode =
      (try? values.decodeIfPresent(UInt16.self, forKey: .pressedKeyCode)) ?? defaults.pressedKeyCode
    trigger =
      (try? values.decodeIfPresent(AutoPressTrigger.self, forKey: .trigger)) ?? defaults.trigger
    pressesPerSecond = Self.clamp(
      (try? values.decodeIfPresent(Int.self, forKey: .pressesPerSecond))
        ?? defaults.pressesPerSecond,
      to: Self.pressesPerSecondRange)
    autoOffEnabled =
      (try? values.decodeIfPresent(Bool.self, forKey: .autoOffEnabled)) ?? defaults.autoOffEnabled
    autoOffMinutes = Self.clamp(
      (try? values.decodeIfPresent(Int.self, forKey: .autoOffMinutes)) ?? defaults.autoOffMinutes,
      to: Self.autoOffMinutesRange)
    if trigger.conflicts(withPressedKey: pressedKeyCode) {
      pressedKeyCode = defaults.pressedKeyCode
      trigger = defaults.trigger
    }
  }

  public static func decode(_ data: Data?) -> AutoPressSettings {
    data.flatMap { try? JSONDecoder().decode(AutoPressSettings.self, from: $0) }
      ?? AutoPressSettings()
  }

  public var pressInterval: TimeInterval { 1 / Double(pressesPerSecond) }
  /// Long enough for a streamed game to register the key, and never longer than half an interval.
  public var holdDuration: TimeInterval { min(0.04, pressInterval / 2) }

  private static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
    min(max(value, range.lowerBound), range.upperBound)
  }
}

/// Whether auto-pressing is switched on, and when it turns itself off.
public struct AutoPressSession: Equatable, Sendable {
  /// Non-nil while switched on, whether or not the target app is currently in front.
  public private(set) var startedAt: Date?

  public init() {}

  public var isOn: Bool { startedAt != nil }

  public mutating func turnOn(at date: Date) { startedAt = date }
  public mutating func turnOff() { startedAt = nil }

  public func autoOffDate(_ settings: AutoPressSettings) -> Date? {
    guard let startedAt, settings.autoOffEnabled else { return nil }
    return startedAt.addingTimeInterval(TimeInterval(settings.autoOffMinutes) * 60)
  }

  public func isExpired(at date: Date, _ settings: AutoPressSettings) -> Bool {
    autoOffDate(settings).map { date >= $0 } ?? false
  }

  public func shouldPress(targetFrontmost: Bool, at date: Date, _ settings: AutoPressSettings)
    -> Bool
  {
    isOn && targetFrontmost && !isExpired(at: date, settings)
  }

  /// `targetRunning` is whether an instance target is still running; it's ignored for an app,
  /// which can always be opened and brought to the front. An instance that has quit won't come
  /// back, so the status doesn't say it's waiting for it. That comes before `targetFrontmost`,
  /// which is only brought up to date when the frontmost app changes.
  public func status(
    targetFrontmost: Bool, targetRunning: Bool = true, at date: Date,
    _ settings: AutoPressSettings, keyName: String
  ) -> String {
    guard isOn else { return "Off" }
    var text: String
    if settings.target.isInstance && !targetRunning {
      text = "On, but \(settings.target.name) has quit"
    } else if targetFrontmost {
      text = "Pressing \(keyName)"
    } else {
      text = "On, paused until \(settings.target.name) is in front"
    }
    if let off = autoOffDate(settings) {
      let minutes = max(1, Int((off.timeIntervalSince(date) / 60).rounded(.up)))
      text += " · off in \(minutes) min"
    }
    return text
  }
}
