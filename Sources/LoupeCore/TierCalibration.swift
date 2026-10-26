import Foundation

public enum ArtifactTier: String, CaseIterable, Sendable {
  case s = "S"
  case a = "A"
  case b = "B"
  case c = "C"
  case d = "D"
}

public struct CharacterGradeSummary: Sendable {
  /// How worth rolling the piece is for the role; see `RollGrade`. Before +20 it grades the
  /// expected +20 score, at +20 the final score.
  public let grade: ArtifactTier
  /// Chance an unfinished piece finishes at or above the A cutoff.
  public let chanceOfAOrBetter: Double?
  /// Share of new drops of this slot and main stat finishing at or above the final score at +20,
  /// or the median projected score before +20.
  public let rarityShare: Double?
  /// The same share for the P90 and best possible +20 outcomes, before +20.
  public let p90Share: Double?
  public let bestShare: Double?
  /// Expected new drops before one of the same set, slot, and main stat beats that score.
  public let replacementDrops: Double?
  public let calibrationID: String
  public let experimental: Bool
}

public enum TierCalibration {
  public static let version = RollGrade.version

  /// Letters come from the role's example starts (`RollGrade`); rarity among new drops of the
  /// same slot and main stat describes the outcomes. A role whose core stats cannot appear as a
  /// substat on this piece fits by main stat only and is ungraded.
  static func evaluate(
    _ artifact: Artifact, role: CharacterRole, potential: Potential?
  ) -> CharacterGradeSummary? {
    guard role.usefulStats.contains(where: { $0 != artifact.main }),
      let rarity = RarityCache.shared.rarity(artifact.slot, artifact.main, role.profile)
    else { return nil }
    let finished = artifact.level == 20 ? role.profile.score(artifact.substats) : nil
    // Without a final score or an ordinary forecast there is nothing to grade.
    guard let score = finished.map(Double.init) ?? potential.map({ $0.expectedScore * 1000 })
    else { return nil }
    let cutoffs = RollGrade.cutoffs(rarity, profile: role.profile)
    let aCutoff = cutoffs.first { $0.tier == .a }!.minimum - 1e-6
    func share(_ score: Double) -> Double { rarity.shareAtOrAbove(Int((score * 1000).rounded())) }
    let headline = finished ?? potential.map { Int(($0.summary.p50Score * 1000).rounded()) }
    let unfinished = finished == nil ? potential : nil
    return CharacterGradeSummary(
      grade: RollGrade.tier(score, cutoffs: cutoffs),
      chanceOfAOrBetter: unfinished.map {
        $0.distribution.reduce(0) { $0 + (Double($1.key) >= aCutoff ? $1.value : 0) }
      },
      rarityShare: headline.map { rarity.shareAtOrAbove($0) },
      p90Share: unfinished.map { share($0.summary.p90Score) },
      bestShare: unfinished.map { share($0.summary.bestPossibleScore) },
      replacementDrops: headline.flatMap { rarity.expectedDropsToBeat($0) },
      calibrationID: "\(version):\(artifact.slot.rawValue).\(artifact.main.rawValue)",
      experimental: true)
  }
}

/// Rarity tables depend only on slot, main stat, and profile weights, so they are shared.
final class RarityCache: @unchecked Sendable {
  static let shared = RarityCache()
  private let lock = NSLock()
  private var tables: [String: DropRarity] = [:]

  func rarity(_ slot: Slot, _ main: Stat, _ profile: Profile) -> DropRarity? {
    let weights = Stat.substats.map { "\(profile.weights[$0, default: 0])" }.joined(separator: ",")
    let key = "\(slot.rawValue)|\(main.rawValue)|\(weights)"
    if let table = lock.withLock({ tables[key] }) { return table }
    guard let table = try? DropRarity(slot: slot, main: main, profile: profile) else { return nil }
    lock.withLock { tables[key] = table }
    return table
  }
}
