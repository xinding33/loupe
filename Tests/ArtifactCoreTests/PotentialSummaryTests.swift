import ArtifactCore
import Foundation
import Testing

@Suite struct PotentialSummaryTests {
  @Test func oneRemainingRollUsesDiscreteOutcomesWithoutInterpolation() throws {
    let artifact = try flower(level: 16, crit: 19.5)
    let result = try Potential.evaluate(
      artifact, profile: Profile("Crit", weights: [.critRate: 100]), inventory: [],
      scope: .offPiece)

    // Scores 5, 5.7, 5.8, 5.9, 6 have masses 12/16, 1/16, 1/16, 1/16, 1/16.
    #expect(
      result.distribution == [5000: 0.75, 5700: 0.0625, 5800: 0.0625, 5900: 0.0625, 6000: 0.0625])
    #expect(abs(result.summary.p50Score - 5) < 1e-10)
    #expect(abs(result.summary.p90Score - 5.9) < 1e-10)
    #expect(abs(result.summary.bestPossibleScore - 6) < 1e-10)
    #expect(result.comparisonCount == 0)
    #expect(result.chanceToBeatBest == nil)
    #expect(result.rankChances.isEmpty)
  }

  @Test func medianAtExactlyHalfTheMassKeepsTheLowerScore() throws {
    let result = try Potential.evaluate(
      flower(level: 16, crit: 19.5),
      profile: Profile("HP + Crit", weights: [.critRate: 100, .hpPercent: 100]),
      inventory: [], scope: .sameSet)

    // Scores 6, 6.7, 6.8, 6.9, 7 have masses 1/2, 1/8, 1/8, 1/8, 1/8.
    #expect(abs(result.summary.p50Score - 6) < 1e-10)
    #expect(abs(result.summary.p90Score - 7) < 1e-10)
    #expect(abs(result.summary.bestPossibleScore - 7) < 1e-10)
  }

  @Test func twoRemainingRollsAccumulateRepeatedOutcomes() throws {
    let result = try Potential.evaluate(
      flower(level: 12, crit: 15.6), profile: Profile("Crit", weights: [.critRate: 100]),
      inventory: [], scope: .offPiece)

    // P(no useful roll) = 9/16. CDF(4.9) = 216/256; CDF(5) = 240/256.
    #expect(abs(result.summary.p50Score - 4) < 1e-10)
    #expect(abs(result.summary.p90Score - 5) < 1e-10)
    #expect(abs(result.summary.bestPossibleScore - 6) < 1e-10)
  }

  @Test func weightedScoresUsePublicUnitsAtNonCheckpointLevels() throws {
    let result = try Potential.evaluate(
      flower(level: 19, crit: 19.5), profile: Profile("Weighted", weights: [.critRate: 37]),
      inventory: [], scope: .offPiece)

    #expect(result.upgradesRemaining == 1)
    #expect(abs(result.summary.p50Score - 1.85) < 1e-10)
    #expect(abs(result.summary.p90Score - 2.183) < 1e-10)
    #expect(abs(result.summary.bestPossibleScore - 2.22) < 1e-10)
  }

  @Test func finishedArtifactCollapsesAllQuantilesAndRetainsTieSemantics() throws {
    let artifact = try flower(level: 20, crit: 23.3)
    let duplicate = try artifact.withID(UUID())
    let result = try Potential.evaluate(
      artifact, profile: Profile("Crit", weights: [.critRate: 100]),
      inventory: [artifact, duplicate], scope: .sameSet)

    #expect(result.upgradesRemaining == 0)
    #expect(abs(result.currentScore - 6) < 1e-10)
    #expect(abs(result.summary.p50Score - 6) < 1e-10)
    #expect(abs(result.summary.p90Score - 6) < 1e-10)
    #expect(abs(result.summary.bestPossibleScore - 6) < 1e-10)
    #expect(result.comparisonCount == 1)
    #expect(result.chanceToBeatBest == 0)
    #expect(result.rankChances.first?.probability == 1)
  }

  @Test func noUsefulSubstatsRemainAZeroPointMass() throws {
    let result = try Potential.evaluate(
      flower(level: 0, crit: 3.9), profile: Profile("EM", weights: [.elementalMastery: 100]),
      inventory: [], scope: .offPiece)

    #expect(result.upgradesRemaining == 5)
    #expect(result.distribution == [0: 1])
    #expect(abs(result.summary.p50Score) < 1e-10)
    #expect(abs(result.summary.p90Score) < 1e-10)
    #expect(abs(result.summary.bestPossibleScore) < 1e-10)
  }

  @Test func knownFourthStatIsActivatedBeforeFourRandomUpgrades() throws {
    let artifact = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 0,
      substats: [Substat(.critRate, 3.9), Substat(.atk, 19.5), Substat(.def, 23.2)],
      unactivated: Substat(.hpPercent, 5.8))
    let result = try Potential.evaluate(
      artifact, profile: Profile("HP", weights: [.hpPercent: 100]), inventory: [],
      scope: .offPiece)

    // Four trials: CDF(1.8) = 135/256; CDF(2.8) = 1863/2048.
    #expect(result.upgradesRemaining == 4)
    #expect(abs(result.currentScore) < 1e-10)
    #expect(abs(result.summary.p50Score - 1.8) < 1e-10)
    #expect(abs(result.summary.p90Score - 2.8) < 1e-10)
    #expect(abs(result.summary.bestPossibleScore - 5) < 1e-10)
  }

  @Test func observedPlumeMatchesIndependentlyEnumeratedOutcomes() throws {
    let artifact = try Artifact(
      setName: "Night of the Sky's Unveiling", slot: .plume, main: .atk, level: 0,
      substats: [Substat(.def, 21), Substat(.hpPercent, 4.1), Substat(.critDamage, 6.2)],
      unactivated: Substat(.critRate, 3.1))
    let result = try Potential.evaluate(
      artifact, profile: Profile.presets[0], inventory: [], scope: .offPiece)

    // Enumerate four draws from [0, 0, 0, 0, 7, 8, 9, 10], then add base 16.
    #expect(abs(result.summary.p50Score - 3.3) < 1e-10)
    #expect(abs(result.summary.p90Score - 4.4) < 1e-10)
    #expect(abs(result.summary.bestPossibleScore - 5.6) < 1e-10)
    #expect(abs(result.summary.bestPossibleScore - result.maximumScore) < 1e-10)
  }

  @Test func invalidProfilesAndUnsupportedRollInputsStillFailClosed() throws {
    let artifact = try flower(level: 0, crit: 3.9)
    #expect(throws: ArtifactError.self) {
      try Potential.evaluate(
        artifact, profile: Profile("Empty", weights: [:]), inventory: [], scope: .offPiece)
    }
    let missing = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 0,
      substats: [Substat(.critRate, 3.9), Substat(.atk, 19.5), Substat(.def, 23.2)])
    #expect(throws: ArtifactError.self) {
      try Potential.evaluate(
        missing, profile: Profile.presets[0], inventory: [], scope: .offPiece)
    }
    let special = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 0,
      substats: artifact.substats, rule: .special)
    #expect(throws: ArtifactError.self) {
      try Potential.evaluate(
        special, profile: Profile.presets[0], inventory: [], scope: .offPiece)
    }
  }

  private func flower(level: Int, crit: Double) throws -> Artifact {
    try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: level,
      substats: [
        Substat(.critRate, crit), Substat(.atk, 19.5), Substat(.def, 23.2),
        Substat(.hpPercent, 5.8),
      ])
  }
}
