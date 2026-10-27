import Foundation

/// The sidebar settings Loupe remembers between launches. Session state, such as a linked upgrade
/// or crafted rolls for the piece on screen, is left out.
public struct Preferences: Codable, Equatable, Sendable {
  public static let weightRange = 0...100
  public static let customProfileName = "Custom"

  public var collectCards = false
  public var bufferDiagnostics = false
  public var overlayExpanded = false
  public var manualProfile = false
  public var sameSet = false
  public var profileName = Profile.presets[0].id
  public var customWeights = Dictionary(uniqueKeysWithValues: Stat.substats.map { ($0, 0) })

  public init() {}

  private enum CodingKeys: String, CodingKey {
    case collectCards, bufferDiagnostics, overlayExpanded, manualProfile, sameSet, profileName
    case customWeights
  }

  /// Tolerates missing, unknown and out-of-range fields so a stored value never blocks launch.
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    func bool(_ key: CodingKeys) -> Bool? { try? values.decodeIfPresent(Bool.self, forKey: key) }
    let defaults = Preferences()
    collectCards = bool(.collectCards) ?? defaults.collectCards
    bufferDiagnostics = bool(.bufferDiagnostics) ?? defaults.bufferDiagnostics
    overlayExpanded = bool(.overlayExpanded) ?? defaults.overlayExpanded
    manualProfile = bool(.manualProfile) ?? defaults.manualProfile
    sameSet = bool(.sameSet) ?? defaults.sameSet
    let name = try? values.decodeIfPresent(String.self, forKey: .profileName)
    profileName = name.flatMap(Self.knownProfile) ?? defaults.profileName
    let weights =
      (try? values.decodeIfPresent([String: Int].self, forKey: .customWeights)) ?? [:]
    customWeights = defaults.customWeights
    for (key, value) in weights {
      guard let stat = Stat(rawValue: key), customWeights[stat] != nil else { continue }
      customWeights[stat] = min(
        max(value, Self.weightRange.lowerBound), Self.weightRange.upperBound)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(collectCards, forKey: .collectCards)
    try values.encode(bufferDiagnostics, forKey: .bufferDiagnostics)
    try values.encode(overlayExpanded, forKey: .overlayExpanded)
    try values.encode(manualProfile, forKey: .manualProfile)
    try values.encode(sameSet, forKey: .sameSet)
    try values.encode(profileName, forKey: .profileName)
    try values.encode(
      Dictionary(uniqueKeysWithValues: customWeights.map { ($0.key.rawValue, $0.value) }),
      forKey: .customWeights)
  }

  private static func knownProfile(_ name: String) -> String? {
    name == customProfileName || Profile.presets.contains { $0.id == name } ? name : nil
  }

  /// The saved preferences, or the defaults when the file is missing or unreadable.
  public static func read(from url: URL) -> Preferences {
    (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) }
      ?? Preferences()
  }

  public func write(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: url, options: .atomic)
  }
}
