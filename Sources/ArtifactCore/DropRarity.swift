import Foundation

/// Where a new five-star artifact comes from. It sets the chance of starting with four substats.
public enum DropSource: String, Sendable, CaseIterable {
  case domain
  case bossOrStrongbox

  /// [Fandom: Artifact Drop Distribution](https://genshin-impact.fandom.com/wiki/Loot_System/Artifact_Drop_Distribution).
  public var fourLineChance: Double {
    switch self {
    case .domain: 0.2
    case .bossOrStrongbox: 0.34
    }
  }
}

extension Slot {
  /// Main-stat odds for a new piece of this slot, from Genshin Optimizer's datamined constants.
  public var mainStatOdds: [Stat: Double] {
    switch self {
    case .flower: [.hp: 1]
    case .plume: [.atk: 1]
    case .sands:
      [
        .hpPercent: 80 / 300, .atkPercent: 80 / 300, .defPercent: 80 / 300,
        .elementalMastery: 30 / 300, .energyRecharge: 30 / 300,
      ]
    case .goblet:
      [
        .hpPercent: 77 / 400, .atkPercent: 77 / 400, .defPercent: 76 / 400,
        .elementalMastery: 10 / 400, .physicalDamage: 20 / 400, .pyroDamage: 20 / 400,
        .hydroDamage: 20 / 400, .electroDamage: 20 / 400, .cryoDamage: 20 / 400,
        .anemoDamage: 20 / 400, .geoDamage: 20 / 400, .dendroDamage: 20 / 400,
      ]
    case .circlet:
      [
        .hpPercent: 22 / 100, .atkPercent: 22 / 100, .defPercent: 22 / 100,
        .elementalMastery: 4 / 100, .critRate: 10 / 100, .critDamage: 10 / 100,
        .healing: 10 / 100,
      ]
    }
  }
}

extension Stat {
  /// Relative chance of this substat when a new line is chosen; existing lines and the main are excluded.
  public var appearanceWeight: Int {
    switch self {
    case .hp, .atk, .def: 6
    case .hpPercent, .atkPercent, .defPercent, .elementalMastery, .energyRecharge: 4
    case .critRate, .critDamage: 3
    default: 0
    }
  }
}

/// How a profile's final +20 score is distributed across every possible new drop of one slot and main stat.
///
/// A piece's share is the fraction of new drops that would finish at or above it. It needs no
/// inventory and no guide-derived cutoffs, and it is comparable across profiles because each
/// profile is measured against its own possible drops. It measures rarity, not damage.
public struct DropRarity: Sendable {
  public let slot: Slot
  public let main: Stat
  public let source: DropSource
  /// Distinct final scores in ascending order, in `Profile.score` units.
  public let scores: [Int]
  /// Probability of each score in `scores`.
  public let probabilities: [Double]
  private let tail: [Double]

  public init(slot: Slot, main: Stat, profile: Profile, source: DropSource = .domain) throws {
    guard slot.mainStatOdds[main] != nil else {
      throw ArtifactError("Invalid five-star level or main stat for this slot.")
    }
    let pool = Stat.substats.filter { $0 != main }
    // Every unordered set of four lines, keyed by its sorted profile weights. A three-line start
    // reveals its fourth line by the same weighted draw, so the final line sets are shared.
    var sets: [[Int]: Double] = [:]
    func draw(_ chosen: [Stat], _ probability: Double) {
      guard chosen.count < 4 else {
        sets[chosen.map { profile.weights[$0, default: 0] }.sorted(), default: 0] += probability
        return
      }
      let remaining = pool.filter { !chosen.contains($0) }
      let total = Double(remaining.reduce(0) { $0 + $1.appearanceWeight })
      for stat in remaining {
        draw(chosen + [stat], probability * Double(stat.appearanceWeight) / total)
      }
    }
    draw([], 1)
    let fourLine = source.fourLineChance
    var distribution: [Int: Double] = [:]
    for (weights, setProbability) in sets {
      // Each line starts with one roll; four-line starts then get five upgrades, three-line starts four.
      var start = [0: 1.0]
      for weight in weights {
        var next: [Int: Double] = [:]
        for (score, probability) in start {
          for tier in 7...10 { next[score + tier * weight, default: 0] += probability / 4 }
        }
        start = next
      }
      var upgraded = start
      for upgrade in 1...5 {
        var next: [Int: Double] = [:]
        for (score, probability) in upgraded {
          for weight in weights {
            for tier in 7...10 { next[score + tier * weight, default: 0] += probability / 16 }
          }
        }
        upgraded = next
        if upgrade == 4 {
          for (score, probability) in upgraded {
            distribution[score, default: 0] += setProbability * (1 - fourLine) * probability
          }
        }
      }
      for (score, probability) in upgraded {
        distribution[score, default: 0] += setProbability * fourLine * probability
      }
    }
    let sorted = distribution.sorted { $0.key < $1.key }
    self.slot = slot
    self.main = main
    self.source = source
    self.scores = sorted.map(\.key)
    self.probabilities = sorted.map(\.value)
    var cumulative = 0.0
    var tail = [Double](repeating: 0, count: sorted.count)
    for index in sorted.indices.reversed() {
      cumulative += sorted[index].value
      tail[index] = min(1, cumulative)
    }
    // Every drop finishes at or above the lowest score; avoid summation drift there.
    if !tail.isEmpty { tail[0] = 1 }
    self.tail = tail
  }

  /// The highest final score any new drop can reach under this profile.
  public var bestScore: Int { scores.last ?? 0 }

  /// Fraction of new drops finishing at or above `score`. Ties count, so the lowest score has share 1.
  public func shareAtOrAbove(_ score: Int) -> Double {
    let index = scores.firstIndex { $0 >= score }
    return index.map { tail[$0] } ?? 0
  }

  /// Fraction of new drops finishing strictly above `score`.
  public func shareAbove(_ score: Int) -> Double {
    score == .max ? 0 : shareAtOrAbove(score + 1)
  }

  /// Expected number of new five-star drops before one of this set, slot, and main stat finishes
  /// strictly above `score`. A domain offers two sets, so `setChance` defaults to one half.
  /// Returns nil when no new drop can beat the score.
  public func expectedDropsToBeat(_ score: Int, setChance: Double = 0.5) -> Double? {
    let chance = setChance / 5 * (slot.mainStatOdds[main] ?? 0) * shareAbove(score)
    return chance > 0 ? 1 / chance : nil
  }
}

/// Tiers from rarity among new drops of the same slot and main stat, under one role's profile.
public enum RarityTier {
  public static let version = "rarity-2026-10-22.1"
  /// Largest share of new drops at or above a piece that still earns each tier.
  public static let bounds: [(tier: ArtifactTier, share: Double)] = [
    (.s, 0.0005), (.a, 0.01), (.b, 0.15), (.c, 0.50),
  ]

  public static func tier(share: Double) -> ArtifactTier {
    bounds.first { share <= $0.share }?.tier ?? .d
  }
}
