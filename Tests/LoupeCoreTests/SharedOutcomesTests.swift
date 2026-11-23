import Foundation
import LoupeCore
import Testing

/// One enumeration shared across the profile, roles and verdict gives exactly what each would
/// compute alone, and an enumeration of another piece is ignored.
@Suite struct SharedOutcomesTests {
  private let pieces: [Artifact]
  private let inventory: [Artifact]

  init() throws {
    pieces = [
      try Artifact(
        setName: "Gilded Dreams", slot: .flower, main: .hp, level: 0,
        substats: [
          Substat(.critRate, 3.9), Substat(.critDamage, 7.8), Substat(.atkPercent, 5.8),
          Substat(.energyRecharge, 6.5),
        ]),
      try Artifact(
        setName: "Golden Troupe", slot: .goblet, main: .hydroDamage, level: 0,
        substats: [Substat(.hpPercent, 5.8), Substat(.critRate, 3.9), Substat(.critDamage, 7.8)],
        unactivated: Substat(.atk, 19)),
      try Artifact(
        setName: "Emblem of Severed Fate", slot: .sands, main: .energyRecharge, level: 8,
        substats: [
          Substat(.critRate, 7.0), Substat(.critDamage, 13.2), Substat(.atkPercent, 5.3),
          Substat(.elementalMastery, 23),
        ]),
      try Artifact(
        setName: "Gilded Dreams", slot: .flower, main: .hp, level: 20,
        substats: [
          Substat(.elementalMastery, 117), Substat(.hpPercent, 5.8), Substat(.critRate, 7.8),
          Substat(.def, 23),
        ]),
      // No odds: a missing fourth line, a special roll, and a four-star piece.
      try Artifact(
        setName: "Golden Troupe", slot: .goblet, main: .hydroDamage, level: 0,
        substats: [Substat(.hpPercent, 5.8), Substat(.critRate, 3.9), Substat(.critDamage, 7.8)]),
      try Artifact(
        setName: "Gilded Dreams", slot: .flower, main: .hp, level: 0,
        substats: [
          Substat(.critRate, 3.9), Substat(.critDamage, 7.8), Substat(.atkPercent, 5.8),
          Substat(.energyRecharge, 6.5),
        ], rule: .special),
      try Artifact(
        setName: "Instructor", slot: .sands, main: .elementalMastery, level: 0,
        substats: [Substat(.energyRecharge, 4.14), Substat(.critRate, 2.49)], rarity: 4),
    ]
    inventory = [
      try Artifact(
        setName: "Gilded Dreams", slot: .flower, main: .hp, level: 20,
        substats: [
          Substat(.critRate, 10.5), Substat(.critDamage, 21.0), Substat(.atkPercent, 9.9),
          Substat(.energyRecharge, 6.5),
        ]),
      try Artifact(
        setName: "Nymph's Dream", slot: .goblet, main: .hydroDamage, level: 20,
        substats: [
          Substat(.hpPercent, 17.5), Substat(.critRate, 7.8), Substat(.critDamage, 14.8),
          Substat(.atk, 38.9),
        ]),
      try Artifact(
        setName: "Emblem of Severed Fate", slot: .sands, main: .energyRecharge, level: 20,
        substats: [
          Substat(.critRate, 10.1), Substat(.critDamage, 20.2), Substat(.atkPercent, 9.3),
          Substat(.def, 23),
        ]),
    ]
  }

  @Test func sharedEnumerationMatchesIndependentResults() throws {
    let other = try RollOutcomes(pieces[0])
    for piece in pieces {
      let profiles = [Profile.presets[0], Profile.presets[2]]
      let alone = profiles.map { profile in
        describe(
          Result {
            try Potential.evaluate(piece, profile: profile, inventory: inventory, scope: .offPiece)
          })
      }
      let matches = CharacterAssessment.evaluate(piece, inventory: inventory)
      let verdict = VerdictEngine.evaluate(piece, matches: matches, inventory: inventory)
      #expect(!matches.isEmpty)
      // Another piece's enumeration must be ignored, not scored.
      for outcomes in [try? RollOutcomes(piece), piece == pieces[0] ? nil : other] {
        let reused = profiles.map { profile in
          describe(
            Result {
              try Potential.evaluate(
                piece, profile: profile, inventory: inventory, scope: .offPiece,
                outcomes: outcomes)
            })
        }
        #expect(reused == alone)
        let sharedMatches = CharacterAssessment.evaluate(
          piece, inventory: inventory, outcomes: outcomes)
        #expect(sharedMatches.map(describe) == matches.map(describe))
        #expect(
          VerdictEngine.evaluate(
            piece, matches: sharedMatches, inventory: inventory, outcomes: outcomes) == verdict)
      }
    }
  }

  private func describe(_ result: Result<Potential, Error>) -> String {
    switch result {
    case .success(let potential): describe(potential)
    case .failure(let error): "error: \(error.localizedDescription)"
    }
  }

  private func describe(_ potential: Potential?) -> String {
    guard let potential else { return "none" }
    let distribution = potential.distribution.sorted { $0.key < $1.key }
      .map { "\($0.key):\($0.value.bitPattern)" }
    return [
      "\(potential.currentScore.bitPattern) \(potential.minimumScore.bitPattern)",
      "\(potential.expectedScore.bitPattern) \(potential.maximumScore.bitPattern)",
      "\(potential.summary) \(potential.upgradesRemaining)",
      "\(potential.comparisonCount) \(String(describing: potential.bestRank))",
      potential.rankChances.map { "\($0.rank):\($0.probability.bitPattern)" }.joined(
        separator: ","),
      String(describing: potential.chanceToBeatBest?.bitPattern),
      potential.leaders.map(\.id.uuidString).joined(separator: ","),
      distribution.joined(separator: ","),
    ].joined(separator: "|")
  }

  private func describe(_ match: CharacterMatch) -> String {
    let grades = match.grades.map { grades in
      [
        grades.grade.rawValue, String(describing: grades.chanceOfAOrBetter?.bitPattern),
        String(describing: grades.rarityShare?.bitPattern),
        String(describing: grades.p90Share?.bitPattern),
        String(describing: grades.bestShare?.bitPattern),
        String(describing: grades.replacementDrops?.bitPattern), grades.calibrationID,
        String(grades.experimental),
      ].joined(separator: " ")
    }
    return [
      match.roleID, String(describing: match.setFit), describe(match.potential),
      match.potentialUnavailableReason ?? "-", grades ?? "ungraded",
      match.reasons.joined(separator: " "),
    ].joined(separator: "|")
  }
}
