import LoupeCore

/// A browsing order based on stat presence and set context, never cross-role strength.
/// The role behind the current verdict, when there is one, leads the list. The visible rows show
/// one role per character and different archetypes before repeating one, since an archetype's
/// characters share a grade. The full list keeps every role, so a character's other roles
/// remain selectable.
struct CharacterShortlist {
  let allMatches: [CharacterMatch]
  let visibleMatches: [CharacterMatch]
  let selectedMatch: CharacterMatch?

  init(
    matches: [CharacterMatch], artifact: Artifact?, selectedCharacterID: String?,
    selectedRoleID: String? = nil, leadingCharacterID: String? = nil, leadingRoleID: String? = nil
  ) {
    guard let artifact else {
      allMatches = []
      visibleMatches = []
      selectedMatch = nil
      return
    }
    func priority(_ match: CharacterMatch) -> (Int, Int, Int, Int, Int, String) {
      let active = artifact.substats.filter { match.usefulStats.contains($0.key) }.count
      // Fixed flower/plume mains do not distinguish users. EM-only mains still count as fit.
      let coreMain =
        artifact.slot != .flower && artifact.slot != .plume
        && match.usefulStats.contains(artifact.main)
      let set = match.setFit == .preferred ? 0 : match.setFit == .alternative ? 1 : 2
      return (
        active > 0 || coreMain ? 0 : 1, set, coreMain ? 0 : 1, -active,
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
    var shown = Set<ArchetypeID?>()
    let varied = characters.filter { shown.insert($0.role.archetype).inserted }
    var visible = Array(
      (varied + characters.filter { match in !varied.contains { $0.roleID == match.roleID } })
        .prefix(5))
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

  /// The character's name, plus the role when the full list holds another role of theirs.
  func label(_ match: CharacterMatch) -> String {
    allMatches.contains { $0.characterID == match.characterID && $0.roleID != match.roleID }
      ? "\(match.characterName) · \(match.roleName)" : match.characterName
  }
}
