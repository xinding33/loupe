import Foundation

public struct Profile: Sendable, Identifiable {
  public let id: String
  public let weights: [Stat: Int]
  public init(_ name: String, weights: [Stat: Int]) {
    self.id = name
    self.weights = weights.filter { Stat.substats.contains($0.key) }.mapValues {
      min(100, max(0, $0))
    }
  }
  public static let presets: [Profile] = [
    Profile("Crit", weights: [.critRate: 100, .critDamage: 100]),
    Profile("ATK + crit", weights: [.atkPercent: 100, .critRate: 100, .critDamage: 100]),
    Profile("HP + crit", weights: [.hpPercent: 100, .critRate: 100, .critDamage: 100]),
    Profile("DEF + crit", weights: [.defPercent: 100, .critRate: 100, .critDamage: 100]),
    Profile("EM + crit", weights: [.elementalMastery: 100, .critRate: 100, .critDamage: 100]),
    Profile("ER + crit", weights: [.energyRecharge: 100, .critRate: 100, .critDamage: 100]),
    Profile("ATK + ER", weights: [.atkPercent: 100, .energyRecharge: 100]),
    Profile("HP + ER", weights: [.hpPercent: 100, .energyRecharge: 100]),
    Profile("DEF + ER", weights: [.defPercent: 100, .energyRecharge: 100]),
    Profile("EM + ER", weights: [.elementalMastery: 100, .energyRecharge: 100]),
    Profile("ATK", weights: [.atkPercent: 100]), Profile("HP", weights: [.hpPercent: 100]),
    Profile("DEF", weights: [.defPercent: 100]), Profile("EM", weights: [.elementalMastery: 100]),
    Profile("ER", weights: [.energyRecharge: 100]),
  ]
  public func score(_ stats: [Substat]) -> Int {
    stats.reduce(0) { sum, stat in
      // Validated displayed totals resolve to the nearest tenth of a max roll.
      sum + Int((stat.value / (stat.key.rolls.last ?? 1) * 10).rounded())
        * weights[stat.key, default: 0]
    }
  }
  public var explanation: String {
    let valued = Stat.substats.filter { weights[$0, default: 0] > 0 }
    if Self.presets.contains(where: { $0.id == id && $0.weights == weights }) {
      return "Valued stats: " + valued.map(\.label).joined(separator: " + ")
    }
    let rolls = valued.map { "\($0.label) \(weights[$0, default: 0])/100" }
    return "Roll weights: " + (rolls.isEmpty ? "none" : rolls.joined(separator: ", "))
  }
}

public enum ComparisonScope: String, CaseIterable, Sendable {
  case offPiece = "All sets (off-piece)"
  case sameSet = "Same set"
}

public struct RankChance: Sendable, Identifiable {
  public let rank: Int
  public let probability: Double
  public var id: Int { rank }
}

public struct Potential: Sendable {
  public let currentScore: Double
  public let minimumScore: Double
  public let expectedScore: Double
  public let maximumScore: Double
  public let summary: PotentialSummary
  public let upgradesRemaining: Int
  public let comparisonCount: Int
  public let bestRank: Int?
  public let rankChances: [RankChance]
  public let chanceToBeatBest: Double?
  public let leaders: [Artifact]
  public let distribution: [Int: Double]

  public static func evaluate(
    _ artifact: Artifact, profile: Profile, inventory: [Artifact],
    scope: ComparisonScope, excluding: UUID? = nil
  ) throws -> Potential {
    guard artifact.rule == .ordinary else {
      throw ArtifactError(
        "Guaranteed-roll and reshaped artifacts are outside the ordinary-roll model.")
    }
    guard profile.weights.values.contains(where: { $0 > 0 }) else {
      throw ArtifactError("Choose at least one useful stat.")
    }
    guard artifact.substats.count == 4 || artifact.unactivated != nil else {
      throw ArtifactError("Read or enter the fourth stat shown as unactivated; it activates at +4.")
    }
    let finalStats = artifact.substats + (artifact.unactivated.map { [$0] } ?? [])
    let events = (20 - artifact.level) / 4 + (artifact.level % 4 == 0 ? 0 : 1)
    let upgrades = events - (artifact.unactivated == nil ? 0 : 1)
    let base = profile.score(finalStats)
    // Each ordinary event chooses one of four stats and one of four roll tiers.
    var increments: [Int: Double] = [:]
    for stat in finalStats {
      for tier in 7...10 {
        increments[tier * profile.weights[stat.key, default: 0], default: 0] += 1.0 / 16
      }
    }
    var distribution = [base: 1.0]
    for _ in 0..<upgrades {
      var next: [Int: Double] = [:]
      for (score, probability) in distribution {
        for (increment, chance) in increments {
          next[score + increment, default: 0] += probability * chance
        }
      }
      distribution = next
    }
    let pool = inventory.filter {
      $0.id != (excluding ?? artifact.id) && $0.level == 20 && $0.slot == artifact.slot
        && $0.main == artifact.main && (scope == .offPiece || $0.setKey == artifact.setKey)
    }.sorted {
      let a = profile.score($0.substats)
      let b = profile.score($1.substats)
      return a == b ? $0.id.uuidString < $1.id.uuidString : a > b
    }
    let scores = pool.map { profile.score($0.substats) }
    let low = distribution.keys.min() ?? base
    let high = distribution.keys.max() ?? base
    var cumulative = 0.0
    var p50 = low
    var p90 = low
    for (score, probability) in distribution.sorted(by: { $0.key < $1.key }) {
      // Retain the first score whose cumulative mass reaches each quantile.
      if cumulative < 0.5 { p50 = score }
      if cumulative < 0.9 { p90 = score }
      cumulative += probability
    }
    let ranks = (0..<min(5, scores.count)).map { index in
      let rank = index + 1
      return RankChance(
        rank: rank,
        probability: distribution.reduce(0) { $0 + ($1.key >= scores[index] ? $1.value : 0) })
    }
    return Potential(
      currentScore: Double(profile.score(artifact.substats)) / 1000,
      minimumScore: Double(low) / 1000,
      expectedScore: distribution.reduce(0) { $0 + Double($1.key) * $1.value } / 1000,
      maximumScore: Double(high) / 1000,
      summary: PotentialSummary(
        p50Score: Double(p50) / 1000, p90Score: Double(p90) / 1000,
        bestPossibleScore: Double(high) / 1000),
      upgradesRemaining: upgrades,
      comparisonCount: pool.count,
      bestRank: pool.isEmpty ? nil : 1 + scores.filter { $0 > high }.count,
      rankChances: ranks,
      chanceToBeatBest: scores.first.map { best in
        distribution.reduce(0) { $0 + ($1.key > best ? $1.value : 0) }
      },
      leaders: Array(pool.prefix(5)), distribution: distribution)
  }
}
