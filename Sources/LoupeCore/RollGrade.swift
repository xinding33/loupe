import Foundation

/// Roll weights for a role, out of 100 per roll.
///
/// Damage roles count a CRIT Rate or CRIT DMG roll as a full roll. Their scaling stat is worth
/// less because sands, goblets, set bonuses and buffers already supply it: an ATK% roll matches a
/// crit roll with no ATK buffer and is about two thirds of one with a big flat-ATK buffer, and
/// HP and DEF have fewer buffers. Supports count every core stat fully. Secondary stats break
/// ties among otherwise equal pieces, such as ER as a damage dealer's fourth line.
public enum RollWeights {
  public static let crit = 100
  public static let atkLike = 75
  public static let hpLike = 85
  public static let support = 100
  public static let secondary = 25

  public static func weights(useful: [Stat], secondary: [Stat]) -> [Stat: Int] {
    let damage = useful.contains(.critRate) && useful.contains(.critDamage)
    var weights: [Stat: Int] = [:]
    for stat in secondary { weights[stat] = Self.secondary }
    for stat in useful {
      switch stat {
      case .critRate, .critDamage: weights[stat] = crit
      case .hpPercent, .defPercent: weights[stat] = damage ? hpLike : support
      default: weights[stat] = damage ? atkLike : support
      }
    }
    return weights
  }
}

/// How worth rolling a piece is, as S to D.
///
/// Each letter has an example start, in its weakest form: every line at its lowest roll and any
/// other line useless. Ranking the build's possible lines by weight:
/// - S: four lines, the four best. In an ATK crit build: CRIT Rate, CRIT DMG, ATK% and ER.
///   Could be one of your best pieces.
/// - A: three lines including the two best, such as double crit. Worth rolling.
/// - B: three lines including the best and the third best, such as one crit and ATK%. Level to
///   +4 and look again.
/// - C: one line of the best stat.
/// - D: less than that.
///
/// A piece earns a letter when its expected +20 score, which counts the rolls it already has,
/// reaches the example's, and when the letter is no more common among the build's finished drops
/// than in an ATK crit build. The second rule matters for narrow builds such as single-stat
/// supports, whose examples are easy to beat once rolls land. A finished piece is graded by its
/// score.
public enum RollGrade {
  public static let version = "roll-2026-10-26.1"
  /// Roll units of the lowest and the average roll; a maximum roll is 10.
  static let lowestRoll = 7
  static let averageRoll = 8.5

  /// The lowest score, in `Profile.score` units, that earns each letter from S down to C.
  public typealias Cutoffs = [(tier: ArtifactTier, minimum: Double)]

  /// Expected +20 scores of the example starts, in `Profile.score` units, from S down to C,
  /// under a profile whose lines are ranked by weight.
  static func examples(main: Stat, profile: Profile) -> [(tier: ArtifactTier, score: Double)] {
    let ranked =
      Stat.substats.filter { $0 != main }.map { profile.weights[$0, default: 0] }
      .sorted(by: >) + [0, 0, 0, 0]
    func start(_ lines: [Int], fourLines: Bool) -> Double {
      let opening = lines.prefix(fourLines ? 4 : 3).reduce(0, +) * lowestRoll
      let mean = Double(lines.reduce(0, +)) / 4
      return Double(opening) + Double(fourLines ? 5 : 4) * mean * averageRoll
    }
    return [
      (.s, start(Array(ranked.prefix(4)), fourLines: true)),
      (.a, start([ranked[0], ranked[1], 0, 0], fourLines: false)),
      (.b, start([ranked[0], ranked[2], 0, 0], fourLines: false)),
      (.c, start([ranked[0], 0, 0, 0], fourLines: false)),
    ]
  }

  static let reference: Profile = {
    let archetype = Archetype.named(.atkCrit)
    return Profile(
      "reference.atk-crit",
      weights: RollWeights.weights(
        useful: archetype.usefulStats, secondary: archetype.secondaryStats))
  }()

  /// Share of finished drops at or above each letter, from S down to C.
  public static let shares: [(tier: ArtifactTier, share: Double)] = {
    let finished = RarityCache.shared.rarity(.plume, .atk, reference)!
    return examples(main: .atk, profile: reference).map {
      ($0.tier, finished.shareAtOrAbove(Int($0.score.rounded(.up))))
    }
  }()

  /// Each letter needs its example's score and a score above every finished score more common
  /// than the letter's share. In the ATK crit build itself the examples decide.
  public static func cutoffs(_ rarity: DropRarity, profile: Profile) -> Cutoffs {
    zip(examples(main: rarity.main, profile: profile), shares).map { example, share in
      let first = rarity.firstIndex(withShareAtMost: share.share)
      // Finished scores are whole units, so anything above the commoner score qualifies.
      let rare = first == 0 ? -Double.infinity : Double(rarity.scores[first - 1]) + 0.5
      return (example.tier, max(example.score, rare))
    }
  }

  public static func tier(_ score: Double, cutoffs: Cutoffs) -> ArtifactTier {
    cutoffs.first { score >= $0.minimum - 1e-6 }?.tier ?? .d
  }
}
