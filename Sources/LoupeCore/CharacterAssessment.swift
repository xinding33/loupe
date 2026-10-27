import Foundation

public struct CharacterMatch: Sendable, Identifiable {
  public let role: CharacterRole
  public let setFit: CharacterSetFit
  public let conditions: [RoleCondition]
  public let reasons: [String]
  public let potential: Potential?
  public let potentialUnavailableReason: String?
  public let grades: CharacterGradeSummary?
  /// A character can hold several roles, so the role identifies a match.
  public var id: String { roleID }
  public var characterID: String { role.characterID }
  public var characterName: String { role.characterName }
  public var roleID: String { role.roleID }
  public var roleName: String { role.roleName }
  public var usefulStats: [Stat] { role.usefulStats }
  public var secondaryStats: [Stat] { role.secondaryStats }
  public var profile: Profile { role.profile }
  /// An on-set role wears this set's pieces, so only those compete with it. An off-piece fills
  /// the build's one off-set slot, which a piece of any set can fill.
  public var scope: ComparisonScope { setFit == .offPiece ? .offPiece : .sameSet }

  /// How likely the build is to wear the piece, highest first. A 4+1 build's one off-set piece
  /// is usually the goblet, sometimes the sands or circlet, and rarely the flower or plume.
  public func wearRank(_ slot: Slot) -> Int {
    switch setFit {
    case .preferred: 3
    case .alternative: 2
    case .offPiece: slot == .goblet ? 2 : isRareOffPiece(slot) ? 0 : 1
    }
  }

  /// An off-set flower or plume: worth listing, never worth keeping a piece for.
  public func isRareOffPiece(_ slot: Slot) -> Bool {
    setFit == .offPiece && (slot == .flower || slot == .plume)
  }
}

public enum CharacterAssessment {
  public static let datasetVersion = CharacterRoles.datasetVersion
  public static let calibrationVersion = TierCalibration.version
  public static let coverageDescription = CharacterRoles.coverageDescription

  /// Potential users in stable identity order, not a cross-role strength ranking. Each role
  /// compares with the saved pieces it would wear instead; see `CharacterMatch.scope`.
  public static func evaluate(
    _ artifact: Artifact, inventory: [Artifact] = [], excluding: UUID? = nil,
    roles: [CharacterRole] = CharacterRoles.all
  ) -> [CharacterMatch] {
    // One enumeration serves every role; a failure is reported per role below.
    let outcomes = try? RollOutcomes(artifact)
    // Characters sharing an archetype and a scope share a forecast, so compute each once.
    struct ForecastKey: Hashable {
      let weights: [Stat: Int]
      let scope: ComparisonScope
    }
    var forecasts: [ForecastKey: Result<Potential, Error>] = [:]
    // A four-star piece is only worth using for a character whose build lists its set.
    let fourStar = artifact.rarity == 4
    return roles.filter { role in
      role.mains[artifact.slot, default: []].contains(artifact.main)
        && (!fourStar || role.sets.contains { Artifact.normalizeSet($0.name) == artifact.setKey })
    }
    .sorted { $0.characterID < $1.characterID }
    .compactMap { role in
      guard !Task.isCancelled else { return nil }
      let set = role.sets.first { Artifact.normalizeSet($0.name) == artifact.setKey }
      let fit = set?.fit ?? .offPiece
      let scope: ComparisonScope = set == nil ? .offPiece : .sameSet
      var conditions = role.conditions
      conditions.append(
        RoleCondition(
          .setActivation,
          set.map {
            "On-set candidate only. Requires \($0.requiredPieces) equipped pieces. \($0.condition)"
          }
            ?? "Off-piece candidate: the other four slots must supply any required four-piece set. Loadout unknown."
        ))
      if artifact.main == .energyRecharge {
        conditions.append(
          RoleCondition(
            .mainStat,
            "ER main is eligible only when the full build needs it; that requirement is unknown.")
        )
      }
      if role.characterID == "kokomi" && artifact.slot == .goblet && artifact.main == .hpPercent {
        conditions.append(
          RoleCondition(
            .mainStat,
            "HP% goblet is a healing alternative; this screen does not compare it with Hydro damage."
          ))
      }
      let active = artifact.substats.filter { role.usefulStats.contains($0.key) }
      var reasons = [
        "\(artifact.main.label) is an eligible \(artifact.slot.label.lowercased()) main for this role."
      ]
      reasons.append(
        active.isEmpty
          ? "No active core substats. Main-stat compatibility alone is not a strong match."
          : "Active core stats: " + active.map { $0.key.label }.joined(separator: ", ") + ".")
      reasons.append(
        "Weighted useful-roll screening, not damage coefficients: " + role.profile.explanation
          + ".")
      if role.usefulStats == [.elementalMastery] && artifact.main == .elementalMastery {
        reasons.append(
          "EM main is useful for this role. An EM substat is impossible here; main-stat fit remains eligible without a core substat score."
        )
      }
      let potential: Potential?
      let unavailable: String?
      if fourStar {
        potential = nil
        unavailable = RollOutcomes.fourStarReason
      } else if !role.usefulStats.contains(where: { $0 != artifact.main }) {
        potential = nil
        unavailable =
          "\(artifact.main.label) main is useful, but this profile has no eligible core substats to compare. Secondary stats alone are not graded."
      } else {
        let key = ForecastKey(weights: role.profile.weights, scope: scope)
        let forecast =
          forecasts[key]
          ?? Result {
            try Potential.evaluate(
              artifact, profile: role.profile, inventory: inventory, scope: scope,
              excluding: excluding, outcomes: outcomes)
          }
        forecasts[key] = forecast
        switch forecast {
        case .success(let value):
          potential = value
          unavailable = nil
        case .failure(let error):
          potential = nil
          unavailable = error.localizedDescription
        }
      }
      let grades = TierCalibration.evaluate(artifact, role: role, potential: potential)
      if grades == nil {
        reasons.append(
          "Ungraded: no final score or forecast, or no core substat can appear on this piece.")
      }
      return CharacterMatch(
        role: role, setFit: fit, conditions: conditions, reasons: reasons,
        potential: potential, potentialUnavailableReason: unavailable, grades: grades)
    }
  }
}
