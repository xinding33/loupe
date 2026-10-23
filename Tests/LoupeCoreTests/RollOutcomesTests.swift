import Foundation
import LoupeCore
import Testing

struct RollOutcomesTests {
  /// The scalar convolution that `Potential.evaluate` used before line outcomes were retained.
  private static func scalarDistribution(_ artifact: Artifact, _ profile: Profile) -> [Int: Double]
  {
    let finalStats = artifact.substats + (artifact.unactivated.map { [$0] } ?? [])
    let events = (20 - artifact.level) / 4 + (artifact.level % 4 == 0 ? 0 : 1)
    let upgrades = events - (artifact.unactivated == nil ? 0 : 1)
    var increments: [Int: Double] = [:]
    for stat in finalStats {
      for tier in 7...10 {
        increments[tier * profile.weights[stat.key, default: 0], default: 0] += 1.0 / 16
      }
    }
    var distribution = [profile.score(finalStats): 1.0]
    for _ in 0..<upgrades {
      var next: [Int: Double] = [:]
      for (score, probability) in distribution {
        for (increment, chance) in increments {
          next[score + increment, default: 0] += probability * chance
        }
      }
      distribution = next
    }
    return distribution
  }

  private static func pieces() throws -> [Artifact] {
    let four = [
      Substat(.critRate, 3.9), Substat(.critDamage, 7.8), Substat(.hpPercent, 5.3),
      Substat(.atk, 16),
    ]
    let raised = [
      Substat(.critRate, 11.7), Substat(.critDamage, 7.8), Substat(.hpPercent, 11.7),
      Substat(.atkPercent, 5.8),
    ]
    return [
      try Artifact(setName: "Test", slot: .flower, main: .hp, level: 0, substats: four),
      try Artifact(setName: "Test", slot: .flower, main: .hp, level: 3, substats: four),
      try Artifact(
        setName: "Test", slot: .flower, main: .hp, level: 0, substats: Array(four.prefix(3)),
        unactivated: Substat(.energyRecharge, 4.5)),
      try Artifact(setName: "Test", slot: .flower, main: .hp, level: 16, substats: raised),
      try Artifact(setName: "Test", slot: .flower, main: .hp, level: 19, substats: raised),
      try Artifact(
        setName: "Test", slot: .goblet, main: .hydroDamage, level: 20,
        substats: [
          Substat(.hpPercent, 17.5), Substat(.critRate, 11.7), Substat(.critDamage, 15.5),
          Substat(.energyRecharge, 6.5),
        ]),
    ]
  }

  @Test func everyProfileReproducesTheScalarDistributionExactly() throws {
    let custom = Profile(
      "Custom", weights: [.critRate: 100, .critDamage: 100, .hpPercent: 50, .atk: 30])
    for artifact in try Self.pieces() {
      let outcomes = try RollOutcomes(artifact)
      for profile in Profile.presets + [custom] {
        #expect(outcomes.scores(profile) == Self.scalarDistribution(artifact, profile))
        #expect(outcomes.currentScore(profile) == profile.score(artifact.substats))
      }
    }
  }

  @Test func outcomesAreDistinctOrderedAndSumToOne() throws {
    for artifact in try Self.pieces() {
      let outcomes = try RollOutcomes(artifact)
      let added = outcomes.upgradesRemaining
      #expect(Set(outcomes.outcomes.map(\.units)).count == outcomes.outcomes.count)
      #expect(
        zip(outcomes.outcomes, outcomes.outcomes.dropFirst()).allSatisfy {
          $0.units.lexicographicallyPrecedes($1.units)
        })
      #expect(abs(outcomes.outcomes.reduce(0) { $0 + $1.probability } - 1) < 1e-12)
      let base = outcomes.outcomes.map { $0.units.reduce(0, +) }.min() ?? 0
      #expect(outcomes.outcomes.allSatisfy { $0.units.reduce(0, +) - base <= 3 * added })
    }
  }

  @Test func aFinishedPieceIsOnePointMass() throws {
    let finished = try Self.pieces().last!
    let outcomes = try RollOutcomes(finished)
    #expect(outcomes.upgradesRemaining == 0)
    #expect(outcomes.outcomes.map(\.units) == [outcomes.currentUnits])
    #expect(outcomes.outcomes.map(\.probability) == [1])
  }

  @Test func aKnownUnactivatedLineCountsOnlyInFinalOutcomes() throws {
    let starter = try Self.pieces()[2]
    let outcomes = try RollOutcomes(starter)
    #expect(outcomes.stats.last == .energyRecharge)
    #expect(outcomes.currentUnits.last == 0)
    #expect(outcomes.upgradesRemaining == 4)
    #expect(outcomes.outcomes.allSatisfy { $0.units.last! >= 7 })
  }

  @Test func crossProfileQuestionsUseTheSameRoll() throws {
    // One event remains, so a top Crit roll and a top HP% roll cannot both happen.
    let piece = try Self.pieces()[4]
    let outcomes = try RollOutcomes(piece)
    let crit = Profile.presets[0]
    let hp = Profile("HP", weights: [.hpPercent: 100])
    #expect(outcomes.currentScore(crit) == 4000)
    #expect(outcomes.currentScore(hp) == 2000)
    let either = outcomes.probability {
      outcomes.score($0.units, profile: crit) >= 5000
        || outcomes.score($0.units, profile: hp) >= 3000
    }
    #expect(either == 3.0 / 16)
  }

  @Test func sharedOutcomesMatchAFreshEvaluation() throws {
    let piece = try Self.pieces()[0]
    let outcomes = try RollOutcomes(piece)
    for profile in Profile.presets {
      let fresh = try Potential.evaluate(piece, profile: profile, inventory: [], scope: .offPiece)
      let shared = try Potential.evaluate(
        piece, profile: profile, inventory: [], scope: .offPiece, outcomes: outcomes)
      #expect(fresh.distribution == shared.distribution)
      #expect(fresh.summary == shared.summary)
    }
  }

  @Test func outcomesOfAnotherReadingAreIgnored() throws {
    let raised = try Self.pieces()[3]
    let finished = try Artifact(
      id: raised.id, setName: "Test", slot: .flower, main: .hp, level: 20,
      substats: try Self.pieces().last!.substats)
    let stale = try RollOutcomes(raised)
    let result = try Potential.evaluate(
      finished, profile: Profile.presets[0], inventory: [], scope: .offPiece, outcomes: stale)
    #expect(result.upgradesRemaining == 0)
    #expect(result.distribution == [5000: 1])

    let missing = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 0,
      substats: [Substat(.critRate, 3.9), Substat(.critDamage, 7.8), Substat(.atk, 16)])
    let error = #expect(throws: ArtifactError.self) {
      try Potential.evaluate(
        missing, profile: Profile.presets[0], inventory: [], scope: .offPiece,
        outcomes: try RollOutcomes(Self.pieces()[0]))
    }
    #expect(error?.message.contains("fourth stat") == true)
  }

  @Test func unsupportedPiecesKeepTheirMessages() throws {
    let special = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 20,
      substats: try Self.pieces().last!.substats, rule: .special)
    #expect(throws: ArtifactError.self) { try RollOutcomes(special) }
    let missing = try Artifact(
      setName: "Test", slot: .flower, main: .hp, level: 0,
      substats: [Substat(.critRate, 3.9), Substat(.critDamage, 7.8), Substat(.atk, 16)])
    let error = #expect(throws: ArtifactError.self) { try RollOutcomes(missing) }
    #expect(error?.message.contains("fourth stat") == true)
  }
}
