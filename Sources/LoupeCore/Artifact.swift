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
  /// Roll values for a rarity: four-star rolls are 80% of five-star ones. Genshin Optimizer's
  /// constants (MIT).
  public func rolls(rarity: Int) -> [Double] {
    guard rarity == 4 else { return rolls }
    switch self {
    case .hp: return [167.30, 191.20, 215.10, 239.00]
    case .atk: return [10.89, 12.45, 14.00, 15.56]
    case .def: return [12.96, 14.82, 16.67, 18.52]
    case .hpPercent, .atkPercent: return [3.26, 3.73, 4.20, 4.66]
    case .defPercent: return [4.08, 4.66, 5.25, 5.83]
    case .elementalMastery: return [13.06, 14.92, 16.79, 18.65]
    case .energyRecharge: return [3.63, 4.14, 4.66, 5.18]
    case .critRate: return [2.18, 2.49, 2.80, 3.11]
    case .critDamage: return [4.35, 4.97, 5.60, 6.22]
    default: return []
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
  /// Lowercase plural for running text; "sands" is already plural.
  public var plural: String { self == .sands ? "sands" : rawValue + "s" }
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
  /// 5, or 4 for four-star pieces, which stop at +16 and are judged by set and main stat only.
  public let rarity: Int

  public init(
    id: UUID = UUID(), setName: String, slot: Slot, main: Stat, level: Int,
    substats: [Substat], unactivated: Substat? = nil, rule: RollRule = .ordinary,
    rarity: Int = 5
  ) throws {
    guard !setName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw ArtifactError("Read or enter the artifact set.")
    }
    guard rarity == 4 || rarity == 5 else {
      throw ArtifactError("Only four- and five-star artifacts are supported.")
    }
    let stars = rarity == 5 ? "five-star" : "four-star"
    guard (0...Self.maxLevel(rarity)).contains(level), slot.mainStats.contains(main) else {
      throw ArtifactError("Invalid \(stars) level or main stat for this slot.")
    }
    // A five-star starts with three or four lines, a four-star with two or three, and each
    // upgrade adds a line until there are four.
    let starts = (rarity - 2)...(rarity - 1)
    guard starts.contains(where: { min(4, $0 + level / 4) == substats.count }) else {
      throw ArtifactError(
        "This many substats is impossible for a \(stars) artifact at +\(level). Check the card.")
    }
    guard unactivated == nil || (level < 4 && substats.count < 4) else {
      throw ArtifactError(
        "An unactivated stat is only valid below +4 on a starter with a free line.")
    }
    let all = substats + (unactivated.map { [$0] } ?? [])
    guard Set(all.map(\.key)).count == all.count, !all.contains(where: { $0.key == main }) else {
      throw ArtifactError("Substats must be distinct and cannot repeat the main stat.")
    }
    var totals: Set<Int> = [0]
    for stat in substats {
      let counts = Self.possibleRollCounts(stat, rarity: rarity)
      guard !counts.isEmpty else {
        throw ArtifactError(
          "Impossible \(stars) value: \(stat.key.label) \(stat.value). Check the reading.")
      }
      totals = Set(totals.flatMap { total in counts.map { total + $0 } })
    }
    let events = level / 4
    // Only starts that leave this many lines count: three lines at +4 mean a two-line start
    // whose upgrade added a line, not a roll.
    let legalTotals =
      level < 4
      ? [substats.count]
      : Set(starts.filter { min(4, $0 + events) == substats.count }.map { $0 + events })
    guard !totals.isDisjoint(with: legalTotals) else {
      throw ArtifactError(
        "The substats contain an impossible number of rolls for +\(level). Check the values.")
    }
    if let unactivated, !Self.possibleRollCounts(unactivated, rarity: rarity).contains(1) {
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
    self.rarity = rarity
  }

  public static func maxLevel(_ rarity: Int) -> Int { rarity == 5 ? 20 : 16 }
  public var maxLevel: Int { Self.maxLevel(rarity) }
  public var isFinished: Bool { level == maxLevel }

  private static let rollSums: [Int: [Stat: [Set<Int>]]] = Dictionary(
    uniqueKeysWithValues: [4, 5].map { rarity in
      (
        rarity,
        Dictionary(
          uniqueKeysWithValues: Stat.substats.map { stat in
            var sums: [Set<Int>] = [[0]]
            let rolls = stat.rolls(rarity: rarity).map { Int(($0 * 100).rounded()) }
            for _ in 1...6 {
              sums.append(Set(sums.last!.flatMap { sum in rolls.map { sum + $0 } }))
            }
            return (stat, sums)
          })
      )
    })

  public static func possibleRollCounts(_ stat: Substat, rarity: Int = 5) -> Set<Int> {
    guard stat.value.isFinite, stat.value > 0, let sums = rollSums[rarity]?[stat.key] else {
      return []
    }
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
      + (rarity == 5 ? "" : "|\(rarity)*")
  }
  public var setKey: String { Self.normalizeSet(setName) }
  public static func normalizeSet(_ text: String) -> String { text.lowercased().filter(\.isLetter) }
  public var nextCheckpoint: Int? { level < maxLevel ? (level / 4 + 1) * 4 : nil }
  public func withID(_ id: UUID) throws -> Artifact {
    try Artifact(
      id: id, setName: setName, slot: slot, main: main, level: level, substats: substats,
      unactivated: unactivated, rule: rule, rarity: rarity)
  }

  public func upgraded(to next: Artifact) throws -> Artifact {
    let before = substats + (unactivated.map { [$0] } ?? [])
    let after = next.substats + (next.unactivated.map { [$0] } ?? [])
    guard setKey == next.setKey, slot == next.slot, main == next.main, rule == next.rule,
      rarity == next.rarity, next.level >= level,
      // A four-star that started with two lines gains lines as it levels.
      Set(before.map(\.key)).isSubset(of: after.map(\.key)),
      next.level >= 4 || next.unactivated == unactivated
    else {
      throw ArtifactError(
        "This does not match the previous artifact. Read its Inventory card first.")
    }
    // Each upgrade either adds a line or rolls one; only the rolls show as value changes.
    let added = after.count - before.count + (unactivated != nil && next.level >= 4 ? 1 : 0)
    let events = next.level / 4 - level / 4 - added
    // A line added since the last reading arrives with one roll and may have rolled since.
    var counts: Set<Int> = [0]
    for line in after where !before.contains(where: { $0.key == line.key }) {
      let extra = Self.possibleRollCounts(line, rarity: rarity).map { $0 - 1 }
      counts = Set(counts.flatMap { count in extra.map { count + $0 } })
    }
    for old in before {
      guard let new = after.first(where: { $0.key == old.key }), new.value >= old.value else {
        throw ArtifactError(
          "A stat decreased. This is not an ordinary upgrade of the previous piece.")
      }
      guard events != 0 || new.value == old.value else {
        throw ArtifactError("A substat changed without an upgrade roll. Waiting for a clear card.")
      }
      let maxRoll = old.key.rolls(rarity: rarity).last ?? 1
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

  enum CodingKeys: CodingKey {
    case id, setName, slot, main, level, substats, unactivated, rule, rarity
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: c.decode(UUID.self, forKey: .id), setName: c.decode(String.self, forKey: .setName),
      slot: c.decode(Slot.self, forKey: .slot), main: c.decode(Stat.self, forKey: .main),
      level: c.decode(Int.self, forKey: .level),
      substats: c.decode([Substat].self, forKey: .substats),
      unactivated: c.decodeIfPresent(Substat.self, forKey: .unactivated),
      rule: c.decode(RollRule.self, forKey: .rule),
      rarity: c.decodeIfPresent(Int.self, forKey: .rarity) ?? 5)
  }
}
