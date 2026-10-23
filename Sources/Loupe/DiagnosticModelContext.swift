import Foundation
import LoupeCore

extension DiagnosticRecommendation {
  static func evaluated(
    _ artifact: Artifact, result: Potential, profile: Profile, pool: [Artifact],
    scope: ComparisonScope, excluded: UUID?, match: CharacterMatch? = nil
  ) -> DiagnosticRecommendation {
    let comparisons = pool.filter {
      $0.id != (excluded ?? artifact.id) && $0.level == 20 && $0.slot == artifact.slot
        && $0.main == artifact.main && (scope == .offPiece || $0.setKey == artifact.setKey)
    }
    var metrics = [
      "currentScore": result.currentScore, "p50Score": result.summary.p50Score,
      "p90Score": result.summary.p90Score, "bestPossibleScore": result.summary.bestPossibleScore,
      "comparisonCount": Double(result.comparisonCount),
    ]
    if let chance = result.chanceToBeatBest { metrics["chanceToBeatBest"] = chance }
    for chance in result.rankChances { metrics["top\(chance.rank)OrTied"] = chance.probability }
    if let chance = match?.grades?.chanceOfAOrBetter { metrics["chanceOfAOrBetter"] = chance }
    let explanation =
      match.map {
        ([profile.explanation, $0.roleID, $0.headline(level: artifact.level), $0.setDescription]
          + $0.reasons + $0.conditions.map(\.explanation)).joined(separator: "\n")
      } ?? profile.explanation
    return DiagnosticRecommendation(
      scoringVersion: "ordinary-max-roll-quantiles-v1"
        + (match == nil ? "" : "/" + CharacterAssessment.calibrationVersion),
      dataVersion: match == nil ? "builtin-profiles-v1" : CharacterAssessment.datasetVersion,
      profile: profile.id, scope: scope.rawValue,
      weights: Dictionary(
        uniqueKeysWithValues: profile.weights.map { ($0.key.rawValue, Double($0.value)) }),
      comparisonPieces: comparisons, excludedID: excluded, metrics: metrics,
      explanation: explanation)
  }
}
