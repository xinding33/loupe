import Foundation

public enum ArtifactTier: String, CaseIterable, Sendable {
  case s = "S"
  case a = "A"
  case b = "B"
  case c = "C"
  case d = "D"
}

public struct CharacterGradeSummary: Sendable {
  public let current: ArtifactTier?
  public let p50: ArtifactTier?
  public let p90: ArtifactTier?
  public let bestPossible: ArtifactTier?
  public let chanceOfAOrBetter: Double?
  /// Share of new drops of this slot and main stat finishing at or above the final score at +20,
  /// or the median projected score before +20.
  public let rarityShare: Double?
  /// Expected new drops before one of the same set, slot, and main stat beats that score.
  public let replacementDrops: Double?
  public let calibrationID: String
  public let experimental: Bool
}

public enum TierCalibration {
  public static let version = RarityTier.version

  /// Tiers come from rarity among new drops of the same slot and main stat under the role's
  /// profile; see `RarityTier`. A profile with no possible core substat on this piece is ungraded.
  static func evaluate(
    _ artifact: Artifact, role: CharacterRole, potential: Potential?
  ) -> CharacterGradeSummary? {
    guard let rarity = RarityCache.shared.rarity(artifact.slot, artifact.main, role.profile),
      rarity.bestScore > 0
    else { return nil }
    func tier(_ score: Double) -> ArtifactTier {
      RarityTier.tier(share: rarity.shareAtOrAbove(Int((score * 1000).rounded())))
    }
    let current = artifact.level == 20 ? role.profile.score(artifact.substats) : nil
    // Without a final score or an ordinary forecast there is nothing to grade.
    guard current != nil || potential != nil else { return nil }
    let headline = current ?? potential.map { Int(($0.summary.p50Score * 1000).rounded()) }
    let aShare = RarityTier.bounds.first { $0.tier == .a }!.share
    return CharacterGradeSummary(
      current: current.map { RarityTier.tier(share: rarity.shareAtOrAbove($0)) },
      p50: potential.map { tier($0.summary.p50Score) },
      p90: potential.map { tier($0.summary.p90Score) },
      bestPossible: potential.map { tier($0.summary.bestPossibleScore) },
      chanceOfAOrBetter: potential.map {
        $0.distribution.reduce(0) { $0 + (rarity.shareAtOrAbove($1.key) <= aShare ? $1.value : 0) }
      },
      rarityShare: headline.map { rarity.shareAtOrAbove($0) },
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
