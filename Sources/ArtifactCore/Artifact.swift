import Foundation

public enum Stat: String, Codable, CaseIterable, Sendable, Identifiable {
  case hp, atk, def
  case hpPercent = "hp_"
  case atkPercent = "atk_"
  case defPercent = "def_"
  case elementalMastery = "eleMas"
  case energyRecharge = "enerRech_"
  case critRate = "critRate_"
  case critDamage = "critDMG_"
  case healing = "heal_"
  case physicalDamage = "physical_dmg_"
  case pyroDamage = "pyro_dmg_"
  case hydroDamage = "hydro_dmg_"
  case electroDamage = "electro_dmg_"
  case cryoDamage = "cryo_dmg_"
  case anemoDamage = "anemo_dmg_"
  case geoDamage = "geo_dmg_"
  case dendroDamage = "dendro_dmg_"

  public var id: String { rawValue }
  public var label: String {
    switch self {
    case .hp: "HP"
    case .atk: "ATK"
    case .def: "DEF"
    case .hpPercent: "HP%"
    case .atkPercent: "ATK%"
    case .defPercent: "DEF%"
    case .elementalMastery: "Elemental Mastery"
    case .energyRecharge: "Energy Recharge"
    case .critRate: "CRIT Rate"
    case .critDamage: "CRIT DMG"
    case .healing: "Healing Bonus"
    default: rawValue.replacingOccurrences(of: "_dmg_", with: " DMG Bonus").capitalized
    }
  }
  public var isPercent: Bool { ![.hp, .atk, .def, .elementalMastery].contains(self) }
  public static let substats: [Stat] = [
    .hp, .atk, .def, .hpPercent, .atkPercent, .defPercent, .elementalMastery, .energyRecharge,
    .critRate, .critDamage,
  ]
  public var rolls: [Double] {
    switch self {
    case .hp: [209.13, 239.00, 268.88, 298.75]
    case .atk: [13.62, 15.56, 17.51, 19.45]
    case .def: [16.20, 18.52, 20.83, 23.15]
    case .hpPercent, .atkPercent: [4.08, 4.66, 5.25, 5.83]
    case .defPercent: [5.10, 5.83, 6.56, 7.29]
    case .elementalMastery: [16.32, 18.65, 20.98, 23.31]
    case .energyRecharge: [4.53, 5.18, 5.83, 6.48]
    case .critRate: [2.72, 3.11, 3.50, 3.89]
    case .critDamage: [5.44, 6.22, 6.99, 7.77]
    default: []
    }
  }
  public func display(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(isPercent ? 1 : 0))) + (isPercent ? "%" : "")
  }
}

public enum Slot: String, Codable, CaseIterable, Sendable, Identifiable {
  case flower, plume, sands, goblet, circlet
  public var id: String { rawValue }
  public var label: String { rawValue.capitalized }
  public var mainStats: [Stat] {
    switch self {
    case .flower: [.hp]
    case .plume: [.atk]
    case .sands: [.hpPercent, .atkPercent, .defPercent, .elementalMastery, .energyRecharge]
    case .goblet:
      [
        .hpPercent, .atkPercent, .defPercent, .elementalMastery, .physicalDamage, .pyroDamage,
        .hydroDamage, .electroDamage,
        .cryoDamage, .anemoDamage, .geoDamage, .dendroDamage,
      ]
    case .circlet:
      [.hpPercent, .atkPercent, .defPercent, .elementalMastery, .critRate, .critDamage, .healing]
    }
  }
}

public struct Substat: Codable, Equatable, Sendable {
  public let key: Stat
  public let value: Double
  public init(_ key: Stat, _ value: Double) {
    self.key = key
    self.value = value
  }
}

public enum RollRule: String, Codable, Sendable, CaseIterable {
  case ordinary, special
}

public struct ArtifactError: LocalizedError, Sendable {
  public let message: String
  public init(_ message: String) { self.message = message }
  public var errorDescription: String? { message }
}

public struct Artifact: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let setName: String
  public let slot: Slot
  public let main: Stat
  public let level: Int
  public let substats: [Substat]
  public let unactivated: Substat?
  public let rule: RollRule

  public init(
    id: UUID = UUID(), setName: String, slot: Slot, main: Stat, level: Int,
    substats: [Substat], unactivated: Substat? = nil, rule: RollRule = .ordinary
  ) throws {
    guard !setName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ArtifactError("Read or enter the artifact set.")
    }
    guard (0...20).contains(level), slot.mainStats.contains(main) else {
      throw ArtifactError("Invalid five-star level or main stat for this slot.")
    }
    guard substats.count == (level < 4 ? 3 : 4) || (level < 4 && substats.count == 4) else {
      throw ArtifactError("Expected three or four substats below +4, and four at +4 or higher.")
    }
    guard unactivated == nil || (level < 4 && substats.count == 3) else {
      throw ArtifactError("An unactivated stat is only valid below +4 on a three-stat starter.")
    }
    let all = substats + (unactivated.map { [$0] } ?? [])
    guard Set(all.map(\.key)).count == all.count, !all.contains(where: { $0.key == main }) else {
      throw ArtifactError("Substats must be distinct and cannot repeat the main stat.")
    }
    var totals: Set<Int> = [0]
    for stat in substats {
      let counts = Self.possibleRollCounts(stat)
      guard !counts.isEmpty else {
        throw ArtifactError(
          "Impossible five-star value: \(stat.key.label) \(stat.value). Check the reading.")
      }
      totals = Set(totals.flatMap { total in counts.map { total + $0 } })
    }
    let events = level / 4
    let legalTotals: Set<Int> = level < 4 ? [substats.count] : [3 + events, 4 + events]
    guard !totals.isDisjoint(with: legalTotals) else {
      throw ArtifactError(
        "The substats contain an impossible number of rolls for +\(level). Check the values.")
    }
    if let unactivated, !Self.possibleRollCounts(unactivated).contains(1) {
      throw ArtifactError("The unactivated stat must be one initial roll.")
    }
    self.id = id
    self.setName = setName.trimmingCharacters(in: .whitespacesAndNewlines)
    self.slot = slot
    self.main = main
    self.level = level
    self.substats = substats
    self.unactivated = unactivated
    self.rule = rule
  }

  private static let rollSums: [Stat: [Set<Int>]] = Dictionary(
    uniqueKeysWithValues: Stat.substats.map { stat in
      var sums: [Set<Int>] = [[0]]
      let rolls = stat.rolls.map { Int(($0 * 100).rounded()) }
      for _ in 1...6 { sums.append(Set(sums.last!.flatMap { sum in rolls.map { sum + $0 } })) }
      return (stat, sums)
    })

  public static func possibleRollCounts(_ stat: Substat) -> Set<Int> {
    guard stat.value.isFinite, stat.value > 0, let sums = rollSums[stat.key] else { return [] }
    // Tables use hundredths; allow their accumulated rounding error, not a whole extra displayed step.
    let tolerance = stat.key.isPercent ? 0.075 : 0.525
    return Set(
      (1...6).filter { count in
        sums[count].contains { abs(Double($0) / 100 - stat.value) < tolerance }
      })
  }

  public var signature: String {
    "\(setKey)|\(slot.rawValue)|\(main.rawValue)|\(level)|\(rule.rawValue)|"
      + substats.sorted { $0.key.rawValue < $1.key.rawValue }.map {
        "\($0.key.rawValue):\($0.value)"
      }.joined(separator: ",") + "|\(unactivated.map { "\($0.key.rawValue):\($0.value)" } ?? "")"
  }
  public var setKey: String { Self.normalizeSet(setName) }
  public static func normalizeSet(_ text: String) -> String { text.lowercased().filter(\.isLetter) }
  public var nextCheckpoint: Int? { level < 20 ? (level / 4 + 1) * 4 : nil }
  public func withID(_ id: UUID) throws -> Artifact {
    try Artifact(
      id: id, setName: setName, slot: slot, main: main, level: level, substats: substats,
      unactivated: unactivated, rule: rule)
  }

  public func upgraded(to next: Artifact) throws -> Artifact {
    let before = substats + (unactivated.map { [$0] } ?? [])
    let after = next.substats + (next.unactivated.map { [$0] } ?? [])
    guard setKey == next.setKey, slot == next.slot, main == next.main, rule == next.rule,
      next.level >= level, Set(before.map(\.key)) == Set(after.map(\.key)),
      next.level >= 4 || next.unactivated == unactivated
    else {
      throw ArtifactError(
        "This does not match the previous artifact. Read its Inventory card first.")
    }
    let activation = unactivated != nil && next.level >= 4 ? 1 : 0
    let events = next.level / 4 - level / 4 - activation
    var counts: Set<Int> = [0]
    for old in before {
      guard let new = after.first(where: { $0.key == old.key }), new.value >= old.value else {
        throw ArtifactError(
          "A stat decreased. This is not an ordinary upgrade of the previous piece.")
      }
      guard events != 0 || new.value == old.value else {
        throw ArtifactError("A substat changed without an upgrade roll. Waiting for a clear card.")
      }
      let maxRoll = old.key.rolls.last ?? 1
      let units =
        Int((new.value / maxRoll * 10).rounded()) - Int((old.value / maxRoll * 10).rounded())
      let possible = units == 0 ? [0] : (1...5).filter { 7 * $0 <= units && units <= 10 * $0 }
      counts = Set(counts.flatMap { count in possible.map { count + $0 } })
    }
    guard counts.contains(events) else {
      throw ArtifactError(
        "The stat changes do not fit the number of upgrade events. Wait for the animation to finish."
      )
    }
    return try next.withID(id)
  }

  enum CodingKeys: CodingKey { case id, setName, slot, main, level, substats, unactivated, rule }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: c.decode(UUID.self, forKey: .id), setName: c.decode(String.self, forKey: .setName),
      slot: c.decode(Slot.self, forKey: .slot), main: c.decode(Stat.self, forKey: .main),
      level: c.decode(Int.self, forKey: .level),
      substats: c.decode([Substat].self, forKey: .substats),
      unactivated: c.decodeIfPresent(Substat.self, forKey: .unactivated),
      rule: c.decode(RollRule.self, forKey: .rule))
  }
}
