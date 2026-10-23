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

/// The app auto-press sends keys to, identified by bundle identifier.
public struct AutoPressTarget: Codable, Hashable, Sendable {
  public var bundleID: String
  public var name: String
  public init(bundleID: String, name: String) {
    self.bundleID = bundleID
    self.name = name
  }
  public static let geforceNow = AutoPressTarget(
    bundleID: "com.nvidia.gfnpc.mall", name: "NVIDIA GeForce NOW")
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

  public func status(
    targetFrontmost: Bool, at date: Date, _ settings: AutoPressSettings, keyName: String
  ) -> String {
    guard isOn else { return "Off" }
    var text =
      targetFrontmost
      ? "Pressing \(keyName)" : "On, paused until \(settings.target.name) is in front"
    if let off = autoOffDate(settings) {
      let minutes = max(1, Int((off.timeIntervalSince(date) / 60).rounded(.up)))
      text += " · off in \(minutes) min"
    }
    return text
  }
}
