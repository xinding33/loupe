import Foundation
import LoupeCore
import Testing

struct StarterPotentialTests {
  @Test func presetExplanationNamesValuedStats() {
    #expect(Profile.presets[0].explanation == "Valued stats: CRIT Rate + CRIT DMG")
  }

  @Test func customExplanationLabelsRollWeightsEvenWhenNamedLikeAPreset() {
    let profile = Profile("Crit", weights: [.critRate: 100, .critDamage: 50, .atk: 0])
    #expect(profile.explanation == "Roll weights: CRIT Rate 100/100, CRIT DMG 50/100")
    #expect(Profile("Custom", weights: [:]).explanation == "Roll weights: none")
  }

  @Test(arguments: [(2.72, 5.44, 700), (3.11, 6.22, 800), (3.50, 6.99, 900), (3.89, 7.77, 1000)])
  func equalCritRollWeightsHaveEqualNormalizedScores(rate: Double, damage: Double, score: Int) {
    #expect(Profile.presets[0].score([Substat(.critRate, rate)]) == score)
    #expect(Profile.presets[0].score([Substat(.critDamage, damage)]) == score)
  }

  @Test func customWeightsScaleNormalizedRolls() {
    let profile = Profile("Custom", weights: [.critRate: 100, .critDamage: 50])
    #expect(profile.score([Substat(.critRate, 3.89)]) == 1000)
    #expect(profile.score([Substat(.critDamage, 7.77)]) == 500)
  }

  @Test(arguments: [0, 3])
  func knownStarterActivationConsumesOneEventAndConditionsTheForecast(level: Int) throws {
    let active = [Substat(.atk, 19.45), Substat(.def, 23.15), Substat(.hpPercent, 5.83)]
    let fourth = Substat(.critRate, 2.72)
    let starter = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: level,
      substats: active, unactivated: fourth)
    let activated = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 4, substats: active + [fourth])
    let before = try Potential.evaluate(
      starter, profile: Profile.presets[0], inventory: [], scope: .offPiece)
    let after = try Potential.evaluate(
      activated, profile: Profile.presets[0], inventory: [], scope: .offPiece)

    #expect(starter.nextCheckpoint == 4)
    #expect(before.upgradesRemaining == 4)
    #expect(before.currentScore == 0)
    #expect(abs(after.currentScore - 0.7) < 1e-10)
    #expect(before.distribution == after.distribution)
    #expect(abs(before.distribution.values.reduce(0, +) - 1) < 1e-10)
    #expect(abs(before.minimumScore - 0.7) < 1e-10)
    #expect(abs(before.expectedScore - 1.55) < 1e-10)
    #expect(abs(before.summary.p50Score - 1.5) < 1e-10)
    #expect(abs(before.summary.p90Score - 2.5) < 1e-10)
    #expect(abs(before.maximumScore - 4.7) < 1e-10)
    #expect(before.distribution[700] == 81.0 / 256)
    #expect(before.distribution[4700] == 1.0 / 65536)
  }

  @Test(arguments: [0, 3])
  func fourActiveStatsKeepAllFiveEvents(level: Int) throws {
    let artifact = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: level,
      substats: [
        Substat(.atk, 19.45), Substat(.def, 23.15), Substat(.hpPercent, 5.83),
        Substat(.critRate, 2.72),
      ])
    let result = try Potential.evaluate(
      artifact, profile: Profile.presets[0], inventory: [], scope: .offPiece)
    #expect(result.upgradesRemaining == 5)
    #expect(abs(result.maximumScore - 5.7) < 1e-10)
    #expect(abs(result.expectedScore - 1.7625) < 1e-10)
    #expect(abs(result.distribution.values.reduce(0, +) - 1) < 1e-10)
  }

  @Test(arguments: [0, 3])
  func absentFourthStatStillFailsClosed(level: Int) throws {
    let artifact = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: level,
      substats: [Substat(.atk, 19.45), Substat(.def, 23.15), Substat(.hpPercent, 5.83)])
    do {
      _ = try Potential.evaluate(
        artifact, profile: Profile.presets[0], inventory: [], scope: .offPiece)
      Issue.record("Missing fourth stat must withhold potential.")
    } catch let error as ArtifactError {
      #expect(error.message.contains("shown as unactivated"))
      #expect(error.message.contains("+4"))
    }
  }

  @Test func specialStarterDoesNotUseOrdinaryActivationOdds() throws {
    let artifact = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 0,
      substats: [Substat(.atk, 19.45), Substat(.def, 23.15), Substat(.hpPercent, 5.83)],
      unactivated: Substat(.critRate, 2.72), rule: .special)
    #expect(throws: ArtifactError.self) {
      try Potential.evaluate(
        artifact, profile: Profile.presets[0], inventory: [], scope: .offPiece)
    }
  }

  @Test func finalThreeStatOriginKeepsPointMassAndTieSemantics() throws {
    let artifact = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 20,
      substats: [
        Substat(.atk, 97.25), Substat(.def, 23.15), Substat(.hpPercent, 5.83),
        Substat(.critRate, 2.72),
      ])
    let duplicate = try artifact.withID(UUID())
    let result = try Potential.evaluate(
      artifact, profile: Profile.presets[0], inventory: [artifact, duplicate], scope: .sameSet)
    #expect(artifact.nextCheckpoint == nil)
    #expect(result.upgradesRemaining == 0)
    #expect(result.distribution == [700: 1])
    #expect(abs(result.currentScore - 0.7) < 1e-10)
    #expect(result.summary.p50Score == result.currentScore)
    #expect(result.summary.p90Score == result.currentScore)
    #expect(result.maximumScore == result.currentScore)
    #expect(result.comparisonCount == 1)
    #expect(result.chanceToBeatBest == 0)
    #expect(result.rankChances.first?.probability == 1)
  }
}
