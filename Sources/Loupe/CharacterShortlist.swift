import LoupeCore

/// The list reads top-down as the reason for the verdict, in the verdict's own order: roles
/// still open before roles set aside (`RoleStanding`), then the roll grade, then how likely the
/// build is to wear the piece, then the rarer result. Grades are rarity among drops, so they
/// compare across roles; they are not damage. The verdict's role leads even where the verdict's
/// special rules pick a lower row, such as a support's grade counting only at S. The visible rows
/// show one role per character and different archetypes before repeating one, since an
/// archetype's characters share a grade. The full list keeps every role, so a character's other
/// roles remain selectable.
struct CharacterShortlist {
  let allMatches: [CharacterMatch]
  let visibleMatches: [CharacterMatch]
  let selectedMatch: CharacterMatch?
  private let standings: [String: RoleStanding]

  init(
    matches: [CharacterMatch], artifact: Artifact?, selectedCharacterID: String?,
    selectedRoleID: String? = nil, leadingCharacterID: String? = nil, leadingRoleID: String? = nil,
    standings: [String: RoleStanding] = [:]
  ) {
    self.standings = standings
    guard let artifact else {
      allMatches = []
      visibleMatches = []
      selectedMatch = nil
      return
    }
    func priority(_ match: CharacterMatch) -> (Int, Int, Int, Double, Int, String) {
      // A main-stat-only fit, such as an EM sands for an EM role, ranks below A and above B, as
      // in the verdict. Fixed flower and plume mains fit everyone, so they do not count. Other
      // ungraded roles come last.
      let mainOnly =
        artifact.slot != .flower && artifact.slot != .plume && match.grades == nil
        && match.usefulStats.contains(artifact.main)
        && !match.usefulStats.contains { $0 != artifact.main }
      let grade =
        match.grades.flatMap { grade in
          ArtifactTier.allCases.firstIndex(of: grade.grade).map { $0 < 2 ? $0 : $0 + 1 }
        } ?? (mainOnly ? 2 : ArtifactTier.allCases.count + 1)
      return (
        standings[match.roleID, default: .open] == .open ? 0 : 1, grade,
        -match.wearRank(artifact.slot), match.grades?.rarityShare ?? 1,
        match.role.isReviewed ? 0 : 1, match.characterID + "|" + match.roleID
      )
    }
    var seenRoles = Set<String>()
    var ordered = matches.sorted { priority($0) < priority($1) }
      .filter { seenRoles.insert($0.roleID).inserted }
    let leading =
      ordered.firstIndex { $0.roleID == leadingRoleID }
      ?? ordered.firstIndex { $0.characterID == leadingCharacterID }
    if let leading {
      ordered.insert(ordered.remove(at: leading), at: 0)
    }
    allMatches = ordered
    let selected =
      ordered.first { $0.roleID == selectedRoleID && $0.characterID == selectedCharacterID }
      ?? ordered.first { $0.characterID == selectedCharacterID } ?? ordered.first
    selectedMatch = selected
    var seenCharacters = Set<String>()
    let characters = ordered.filter { seenCharacters.insert($0.characterID).inserted }
    // Variety applies within the open roles, then within the set-aside ones, so a set-aside role
    // of a new archetype never hides an open one.
    func varied(_ group: [CharacterMatch]) -> [CharacterMatch] {
      var shown = Set<ArchetypeID?>()
      let first = group.filter { shown.insert($0.role.archetype).inserted }
      return first + group.filter { match in !first.contains { $0.roleID == match.roleID } }
    }
    let open = characters.filter { standings[$0.roleID, default: .open] == .open }
    let setAside = characters.filter { standings[$0.roleID, default: .open] != .open }
    var visible = Array((varied(open) + varied(setAside)).prefix(5))
    if let selected {
      if let index = visible.firstIndex(where: { $0.characterID == selected.characterID }) {
        visible[index] = selected
      } else {
        visible.removeLast()
        visible.append(selected)
      }
    }
    visibleMatches = visible
  }

  func standing(_ match: CharacterMatch) -> RoleStanding {
    standings[match.roleID, default: .open]
  }

  /// The character's name, plus the role when the full list holds another role of theirs.
  func label(_ match: CharacterMatch) -> String {
    allMatches.contains { $0.characterID == match.characterID && $0.roleID != match.roleID }
      ? "\(match.characterName) · \(match.roleName)" : match.characterName
  }
}
