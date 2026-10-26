import LoupeCore

/// A browsing order based on stat presence and set context, never cross-role strength.
/// The character behind the current verdict, when there is one, leads the list, and the visible
/// rows show different archetypes before repeating one, since an archetype's characters share
/// a grade.
struct CharacterShortlist {
  let allMatches: [CharacterMatch]
  let visibleMatches: [CharacterMatch]
  let selectedMatch: CharacterMatch?

  init(
    matches: [CharacterMatch], artifact: Artifact?, selectedCharacterID: String?,
    leadingCharacterID: String? = nil
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
    var seen = Set<String>()
    var ordered = matches.sorted { priority($0) < priority($1) }
      .filter { seen.insert($0.characterID).inserted }
    if let index = ordered.firstIndex(where: { $0.characterID == leadingCharacterID }) {
      ordered.insert(ordered.remove(at: index), at: 0)
    }
    allMatches = ordered
    let selected = ordered.first { $0.characterID == selectedCharacterID } ?? ordered.first
    selectedMatch = selected
    var shown = Set<ArchetypeID?>()
    let varied = ordered.filter { shown.insert($0.role.archetype).inserted }
    var visible = Array(
      (varied + ordered.filter { match in !varied.contains { $0.roleID == match.roleID } })
        .prefix(5))
    if let selected, !visible.contains(where: { $0.characterID == selected.characterID }) {
      visible.removeLast()
      visible.append(selected)
    }
    visibleMatches = visible
  }
}
