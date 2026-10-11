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
  public let calibrationID: String
  public let experimental: Bool
}

public enum TierCalibration {
  public static let version = "experimental-reviewed-2026-09-27.1"

  private struct Cell {
    let id: String
    let c: Int
    let b: Int
    let a: Int
    let s: Int

    func grade(_ score: Int) -> ArtifactTier {
      if score >= s { return .s }
      if score >= a { return .a }
      if score >= b { return .b }
      if score >= c { return .c }
      return .d
    }

    func grade(_ score: Double) -> ArtifactTier {
      grade(Int((score * 1000).rounded()))
    }
  }

  // Reviewed experimental anchors, not guide-derived damage or universal roll thresholds.
  private static func cell(_ artifact: Artifact, roleID: String) -> Cell? {
    switch (roleID, artifact.slot, artifact.main) {
    case ("furina.off-field-hp", .goblet, .hydroDamage):
      Cell(id: "furina.hydro-goblet", c: 1400, b: 3500, a: 5600, s: 7000)
    case ("itto.on-field-def", .goblet, .geoDamage):
      Cell(id: "itto.geo-goblet", c: 1400, b: 3500, a: 5600, s: 7000)
    case ("kuki-shinobu.hyperbloom", .flower, .hp):
      Cell(id: "kuki.em-flower", c: 700, b: 2100, a: 3500, s: 4900)
    case ("kuki-shinobu.hyperbloom", .plume, .atk):
      Cell(id: "kuki.em-plume", c: 700, b: 2100, a: 3500, s: 4900)
    case ("furina.off-field-hp", .flower, .hp):
      Cell(id: "furina.hp-flower", c: 1400, b: 3500, a: 5600, s: 7000)
    case ("furina.off-field-hp", .plume, .atk):
      Cell(id: "furina.atk-plume", c: 1400, b: 3500, a: 5600, s: 7000)
    case ("itto.on-field-def", .flower, .hp):
      Cell(id: "itto.hp-flower", c: 1400, b: 3500, a: 5600, s: 7000)
    case ("itto.on-field-def", .plume, .atk):
      Cell(id: "itto.atk-plume", c: 1400, b: 3500, a: 5600, s: 7000)
    case ("furina.off-field-hp", .sands, .hpPercent):
      Cell(id: "furina.hp-sands", c: 1400, b: 2800, a: 4900, s: 6000)
    case ("furina.off-field-hp", .goblet, .hpPercent):
      Cell(id: "furina.hp-goblet", c: 1400, b: 2800, a: 4900, s: 6000)
    case ("itto.on-field-def", .sands, .defPercent):
      Cell(id: "itto.def-sands", c: 1400, b: 2800, a: 4900, s: 6000)
    case ("furina.off-field-hp", .circlet, .critRate):
      Cell(id: "furina.cr-circlet", c: 1400, b: 2800, a: 4900, s: 6000)
    case ("furina.off-field-hp", .circlet, .critDamage):
      Cell(id: "furina.cd-circlet", c: 1400, b: 2800, a: 4900, s: 6000)
    case ("itto.on-field-def", .circlet, .critRate):
      Cell(id: "itto.cr-circlet", c: 1400, b: 2800, a: 4900, s: 6000)
    case ("itto.on-field-def", .circlet, .critDamage):
      Cell(id: "itto.cd-circlet", c: 1400, b: 2800, a: 4900, s: 6000)
    default: nil
    }
  }

  static func evaluate(
    _ artifact: Artifact, role: CharacterRole, potential: Potential?
  ) -> CharacterGradeSummary? {
    guard let cell = cell(artifact, roleID: role.roleID) else { return nil }
    // Current tiers require the final main-stat magnitude; unfinished pieces use +20 projections.
    return CharacterGradeSummary(
      current: artifact.level == 20 ? cell.grade(role.profile.score(artifact.substats)) : nil,
      p50: potential.map { cell.grade($0.summary.p50Score) },
      p90: potential.map { cell.grade($0.summary.p90Score) },
      bestPossible: potential.map { cell.grade($0.summary.bestPossibleScore) },
      chanceOfAOrBetter: potential.map {
        $0.distribution.reduce(0) { $0 + ($1.key >= cell.a ? $1.value : 0) }
      },
      calibrationID: cell.id, experimental: true)
  }
}
