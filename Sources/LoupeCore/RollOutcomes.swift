import Foundation

/// Every ordinary +20 outcome of one artifact, keeping each substat line's roll total.
///
/// Profiles score outcomes after enumeration, so one enumeration serves every character
/// and supports questions across profiles, such as the chance of a strong result for any role.
public struct RollOutcomes: Sendable {
  public struct Outcome: Sendable, Equatable {
    /// Final roll units per line, in the order of `RollOutcomes.stats`.
    public let units: [Int]
    public let probability: Double
  }

  /// The artifact these outcomes describe.
  public let artifact: Artifact
  /// Activated substats in card order, followed by a known unactivated stat.
  public let stats: [Stat]
  /// Current activated roll units per line. A known unactivated line counts zero.
  public let currentUnits: [Int]
  public let upgradesRemaining: Int
  /// Distinct final outcomes in ascending lexicographic unit order; probabilities sum to one.
  public let outcomes: [Outcome]

  public static let fourStarReason =
    "Four-star pieces are judged by set and main stat; their roll odds are not modelled."

  /// One maximum-sized roll is 10 units; validated displayed totals resolve to the nearest unit.
  public static func units(_ stat: Substat) -> Int {
    Int((stat.value / (stat.key.rolls.last ?? 1) * 10).rounded())
  }

  public init(_ artifact: Artifact) throws {
    guard artifact.rule == .ordinary else {
      throw ArtifactError(
        "Guaranteed-roll and reshaped artifacts are outside the ordinary-roll model.")
    }
    guard artifact.rarity == 5 else { throw ArtifactError(Self.fourStarReason) }
    guard artifact.substats.count == 4 || artifact.unactivated != nil else {
      throw ArtifactError("Read or enter the fourth stat shown as unactivated; it activates at +4.")
    }
    let lines = artifact.substats + (artifact.unactivated.map { [$0] } ?? [])
    let events = (20 - artifact.level) / 4 + (artifact.level % 4 == 0 ? 0 : 1)
    let upgrades = events - (artifact.unactivated == nil ? 0 : 1)
    let base = lines.map(Self.units)
    // Each ordinary event chooses one of four lines and one of four roll tiers.
    var distribution = [base: 1.0]
    for _ in 0..<upgrades {
      var next: [[Int]: Double] = [:]
      for (units, probability) in distribution {
        for line in units.indices {
          for tier in 7...10 {
            var rolled = units
            rolled[line] += tier
            next[rolled, default: 0] += probability / 16
          }
        }
      }
      distribution = next
    }
    self.artifact = artifact
    self.stats = lines.map(\.key)
    self.currentUnits = artifact.substats.map(Self.units) + (artifact.unactivated == nil ? [] : [0])
    self.upgradesRemaining = upgrades
    self.outcomes = distribution.map { Outcome(units: $0.key, probability: $0.value) }
      .sorted { $0.units.lexicographicallyPrecedes($1.units) }
  }

  /// The profile's score for given line units, in the same integer units as `Profile.score`.
  public func score(_ units: [Int], profile: Profile) -> Int {
    zip(stats, units).reduce(0) { $0 + $1.1 * profile.weights[$1.0, default: 0] }
  }

  public func currentScore(_ profile: Profile) -> Int { score(currentUnits, profile: profile) }

  /// Final score distribution for one profile, keyed like `Potential.distribution`.
  public func scores(_ profile: Profile) -> [Int: Double] {
    let weights = stats.map { profile.weights[$0, default: 0] }
    return outcomes.reduce(into: [:]) { result, outcome in
      let score = zip(weights, outcome.units).reduce(0) { $0 + $1.0 * $1.1 }
      result[score, default: 0] += outcome.probability
    }
  }

  /// Probability mass of final outcomes meeting a condition, such as any profile clearing a bar.
  public func probability(where condition: (Outcome) -> Bool) -> Double {
    outcomes.reduce(0) { condition($1) ? $0 + $1.probability : $0 }
  }
}
