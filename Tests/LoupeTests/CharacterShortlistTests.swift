import AppKit
import Foundation
import SwiftUI
import Testing

@testable import Loupe
@testable import LoupeCore

@MainActor
@Test func shortlistLeadsWithTheVerdictAndKeepsTheEMMainOnlyFit() async throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  model.current = try Artifact(
    setName: "Flower of Paradise Lost", slot: .sands, main: .elementalMastery, level: 0,
    substats: [
      Substat(.hpPercent, 5.83), Substat(.critRate, 3.89), Substat(.def, 23.15),
      Substat(.energyRecharge, 6.48),
    ])
  await model.evaluate()?.value
  // HP%, CRIT Rate and ER on a four-line start grade A for HP reaction damage dealers, which
  // outranks a main-stat-only fit. The EM-only role that wants this set stays in view.
  let selected = try #require(model.selectedMatch)
  #expect(selected.roleID == model.verdict?.roleID)
  #expect(selected.grades?.grade == .a)
  #expect(model.verdict?.title == "Level to +4")
  #expect(model.characterShortlist.visibleMatches.first?.roleID == selected.roleID)
  let fit = try #require(
    model.characterShortlist.visibleMatches.first { $0.usefulStats == [.elementalMastery] })
  #expect(fit.setFit == .preferred)
  #expect(fit.potential == nil)
  #expect(fit.grades == nil)
}

private func shortlistFlower() throws -> Artifact {
  try Artifact(
    setName: "Golden Troupe", slot: .flower, main: .hp, level: 20,
    substats: [
      Substat(.critRate, 23.34), Substat(.critDamage, 7.77), Substat(.atk, 19.45),
      Substat(.def, 23.15),
    ])
}

// Test-only identities exercise expansion without adding unreviewed production roles.
private func syntheticMatch(
  _ id: String, artifact: Artifact, usefulStats: [Stat] = [.critRate],
  setFit: CharacterSetFit = .offPiece
) throws -> CharacterMatch {
  let role = CharacterRole(
    characterID: id, characterName: id.capitalized, roleID: id + ".synthetic",
    roleName: "Synthetic shortlist test", mains: [artifact.slot: [artifact.main]],
    usefulStats: usefulStats, secondaryStats: [], sets: [], conditions: [],
    source: RoleSource(
      url: "https://example.invalid/synthetic", section: "Synthetic test only",
      sourceVersion: "test", reviewedOn: "2026-09-27"))
  let potential =
    usefulStats.contains(where: { $0 != artifact.main })
    ? try Potential.evaluate(artifact, profile: role.profile, inventory: [], scope: .offPiece)
    : nil
  return CharacterMatch(
    role: role, setFit: setFit, conditions: [], reasons: [], potential: potential,
    potentialUnavailableReason: potential == nil ? "No eligible core substats" : nil, grades: nil)
}

private func expandedMatches(_ artifact: Artifact) throws -> [CharacterMatch] {
  try ["ada", "anna", "dorothy", "evelyn", "grace", "margaret"].map {
    try syntheticMatch($0, artifact: artifact)
  }
}

@MainActor
@Test func shortlistIncludesManualChoiceBeyondFiveAndLeavesProfileUntouched() throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  let artifact = try shortlistFlower()
  model.current = artifact
  model.characterMatches = try expandedMatches(artifact)
  model.potential = try Potential.evaluate(
    artifact, profile: model.profile, inventory: [], scope: .offPiece)
  let manualScore = model.potential?.currentScore
  #expect(model.selectedMatch?.characterID == "ada")
  #expect(!model.characterShortlist.visibleMatches.contains { $0.characterID == "margaret" })

  model.selectedCharacterID = "margaret"
  #expect(model.selectedMatch?.characterID == "margaret")
  #expect(
    model.characterShortlist.visibleMatches.map(\.characterID) == [
      "ada", "anna", "dorothy", "evelyn", "margaret",
    ])
  #expect(model.characterShortlist.allMatches.count == 6)
  #expect(model.profileName == "Crit")
  model.assessmentMode = .profile
  #expect(model.displayedPotential?.currentScore == manualScore)
  model.assessmentMode = .characters
  #expect(model.selectedMatch?.characterID == "margaret")
  #expect(model.displayedPotential?.currentScore == 6)
}

@Test func shortlistDeduplicatesAndOrdersIndependentlyOfInputOrder() throws {
  let artifact = try shortlistFlower()
  let matches = try expandedMatches(artifact)
  let forward = CharacterShortlist(matches: matches, artifact: artifact, selectedCharacterID: nil)
  let reversed = CharacterShortlist(
    matches: Array(matches.reversed()) + matches, artifact: artifact, selectedCharacterID: nil)
  #expect(
    forward.allMatches.map(\.characterID) == [
      "ada", "anna", "dorothy", "evelyn", "grace", "margaret",
    ])
  #expect(reversed.allMatches.map(\.characterID) == forward.allMatches.map(\.characterID))
  #expect(reversed.visibleMatches.map(\.characterID) == forward.visibleMatches.map(\.characterID))
  #expect(Set(reversed.visibleMatches.map(\.characterID)).count == 5)
}

@Test func shortlistDoesNotPreferLargerRawCrossRoleScore() throws {
  let artifact = try Artifact(
    setName: "Gilded Dreams", slot: .flower, main: .hp, level: 20,
    substats: [
      Substat(.critRate, 3.89), Substat(.defPercent, 36.45), Substat(.hpPercent, 5.83),
      Substat(.atk, 38.90),
    ])
  let matches = CharacterAssessment.evaluate(artifact)
    .filter { ["furina", "itto"].contains($0.characterID) }
  let furina = try #require(matches.first { $0.characterID == "furina" })
  let itto = try #require(matches.first { $0.characterID == "itto" })
  #expect(try #require(furina.potential).currentScore < #require(itto.potential).currentScore)
  let shortlist = CharacterShortlist(matches: matches, artifact: artifact, selectedCharacterID: nil)
  #expect(shortlist.selectedMatch?.characterID == "furina")
}

@Test func shortlistDoesNotPreferCalibratedKukiOverUngradedActiveCritFit() throws {
  let artifact = try shortlistFlower()
  let matches = CharacterAssessment.evaluate(artifact)
  let kuki = try #require(matches.first { $0.characterID == "kuki-shinobu" })
  #expect(kuki.grades?.grade == .d)
  let shortlist = CharacterShortlist(matches: matches, artifact: artifact, selectedCharacterID: nil)
  #expect(shortlist.selectedMatch?.characterID != "kuki-shinobu")
  #expect(shortlist.selectedMatch?.usefulStats.contains(.critRate) == true)
  #expect(shortlist.selectedMatch?.setFit == .preferred)
  let selectedShare = try #require(shortlist.selectedMatch?.grades?.rarityShare)
  #expect(selectedShare < (try #require(kuki.grades?.rarityShare)))
}

@MainActor
@Test func shortlistRetainsSelectionBeyondFiveRealReviewedMatches() async throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  model.current = try shortlistFlower()
  await model.evaluate()?.value
  let all = model.characterShortlist.allMatches
  #expect(all.count > 5)
  let last = try #require(all.last)
  #expect(!model.characterShortlist.visibleMatches.contains { $0.characterID == last.characterID })
  model.selectedCharacterID = last.characterID
  let shortlist = model.characterShortlist
  #expect(model.selectedMatch?.characterID == last.characterID)
  #expect(shortlist.visibleMatches.count == 5)
  #expect(shortlist.visibleMatches.contains { $0.characterID == last.characterID })
  #expect(Set(shortlist.visibleMatches.map(\.characterID)).count == 5)
  #expect(shortlist.allMatches.map(\.characterID) == all.map(\.characterID))
  #expect(
    Set(shortlist.allMatches.map(\.characterID)) == Set(model.characterMatches.map(\.characterID)))
}

@Test func shortlistPreservesActiveCoreBeforeSetAndSetBeforeIdentity() throws {
  let artifact = try shortlistFlower()
  let inactivePreferred = try syntheticMatch(
    "ada", artifact: artifact, usefulStats: [.elementalMastery], setFit: .preferred)
  let activeOffPiece = try syntheticMatch("anna", artifact: artifact)
  let activeAlternative = try syntheticMatch("grace", artifact: artifact, setFit: .alternative)
  let activePreferred = try syntheticMatch("margaret", artifact: artifact, setFit: .preferred)
  let shortlist = CharacterShortlist(
    matches: [inactivePreferred, activeOffPiece, activeAlternative, activePreferred],
    artifact: artifact, selectedCharacterID: nil)
  #expect(shortlist.allMatches.map(\.characterID) == ["margaret", "grace", "anna", "ada"])
}

@Test func shortlistCoreMainFitSurvivesMoreThanFiveActiveCritUsers() throws {
  let artifact = try Artifact(
    setName: "Golden Troupe", slot: .sands, main: .elementalMastery, level: 20,
    substats: [
      Substat(.critRate, 23.34), Substat(.critDamage, 7.77), Substat(.atk, 19.45),
      Substat(.def, 23.15),
    ])
  let kuki = try #require(
    CharacterAssessment.evaluate(artifact).first { $0.characterID == "kuki-shinobu" })
  let shortlist = CharacterShortlist(
    matches: try expandedMatches(artifact) + [kuki], artifact: artifact, selectedCharacterID: nil)
  #expect(shortlist.allMatches.count == 7)
  #expect(shortlist.visibleMatches.count == 5)
  #expect(shortlist.selectedMatch?.characterID == "kuki-shinobu")
  #expect(shortlist.selectedMatch?.potential == nil)
  #expect(shortlist.selectedMatch?.grades == nil)
}

@Test(arguments: [Slot.flower, .plume])
func shortlistFixedMainDoesNotCountAsCoreFit(slot: Slot) throws {
  let artifact = try Artifact(
    setName: "Golden Troupe", slot: slot, main: slot == .flower ? .hp : .atk, level: 0,
    substats: [Substat(.critRate, 3.89), Substat(.hpPercent, 5.83), Substat(.def, 23.15)],
    unactivated: Substat(.elementalMastery, 23.31))
  let fixedMain = try syntheticMatch("ada", artifact: artifact, usefulStats: [artifact.main])
  let futureCore = try syntheticMatch(
    "anna", artifact: artifact, usefulStats: [.elementalMastery], setFit: .preferred)
  let active = try syntheticMatch("grace", artifact: artifact)
  let shortlist = CharacterShortlist(
    matches: [fixedMain, futureCore, active], artifact: artifact, selectedCharacterID: nil)
  #expect(shortlist.allMatches.map(\.characterID) == ["grace", "anna", "ada"])
}

@Test func shortlistEmptyAndUnavailableSelectionDoNotInventCandidates() throws {
  let artifact = try shortlistFlower()
  let empty = CharacterShortlist(matches: [], artifact: artifact, selectedCharacterID: "ada")
  #expect(empty.selectedMatch == nil)
  #expect(empty.visibleMatches.isEmpty)
  let matches = try expandedMatches(artifact)
  let missing = CharacterShortlist(
    matches: matches, artifact: artifact, selectedCharacterID: "missing")
  #expect(missing.selectedMatch?.characterID == "ada")
  let noArtifact = CharacterShortlist(matches: matches, artifact: nil, selectedCharacterID: "ada")
  #expect(noArtifact.selectedMatch == nil)
  #expect(noArtifact.allMatches.isEmpty)
  #expect(noArtifact.visibleMatches.isEmpty)
}

@MainActor
@Test func shortlistClearsDuringEvaluationAndRejectsStaleResults() async throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  model.current = try shortlistFlower()
  await model.evaluate()?.value
  model.selectedCharacterID = "furina"
  #expect(model.selectedMatch?.characterID == "furina")
  let stale = model.evaluate()
  #expect(model.characterShortlist.visibleMatches.isEmpty)
  #expect(model.selectedMatch == nil)
  let next = try Artifact(
    setName: "Husk of Opulent Dreams", slot: .goblet, main: .geoDamage, level: 0,
    substats: [
      Substat(.critRate, 3.89), Substat(.defPercent, 7.29), Substat(.def, 23.15),
      Substat(.energyRecharge, 6.48),
    ])
  model.current = next
  let fresh = model.evaluate()
  await stale?.value
  await fresh?.value
  #expect(model.current?.signature == next.signature)
  #expect(model.selectedMatch?.characterID == "itto")
  #expect(!model.characterShortlist.allMatches.contains { $0.characterID == "furina" })
  let pending = model.evaluate()
  model.setEnabled(false)
  await pending?.value
  #expect(model.current == nil)
  #expect(model.characterShortlist.visibleMatches.isEmpty)
  #expect(model.selectedMatch == nil)
  #expect(model.displayedPotential == nil)
}

@MainActor
@Test func shortlistRendersExpandedCoverageWhenRequested() throws {
  guard let output = ProcessInfo.processInfo.environment["LOUPE_UI_PROOF"] else { return }
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  let artifact = try shortlistFlower()
  model.current = artifact
  model.characterMatches = CharacterAssessment.evaluate(artifact)
  #expect(model.characterShortlist.allMatches.count > 5)
  let selected = try #require(model.characterShortlist.allMatches.last)
  model.selectedCharacterID = selected.characterID
  model.overlayExpanded = true
  #expect(
    model.characterShortlist.visibleMatches.contains { $0.characterID == selected.characterID })
  try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
  let overlay = ImageRenderer(content: OverlayView(model: model).frame(width: 360, height: 602))
  overlay.scale = 2
  let image = try #require(overlay.cgImage)
  let data = try #require(
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
  try data.write(
    to: URL(fileURLWithPath: output).appending(path: "shortlist-expanded.png"),
    options: .withoutOverwriting)

  let host = NSHostingView(
    rootView: CharacterAssessmentView(model: model, artifact: artifact)
      .padding(16).frame(width: 850, height: 400, alignment: .topLeading)
      .background(Theme.hud).environment(\.colorScheme, .dark))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 850, height: 400), styleMask: [.borderless],
    backing: .buffered, defer: false)
  window.appearance = NSAppearance(named: .darkAqua)
  window.contentView = host
  host.frame = window.contentLayoutRect
  host.layoutSubtreeIfNeeded()
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  let dashboardData = try #require(bitmap.representation(using: .png, properties: [:]))
  try dashboardData.write(
    to: URL(fileURLWithPath: output).appending(path: "shortlist-dashboard.png"),
    options: .withoutOverwriting)
}

@Test func verdictCharacterLeadsUnlessTheUserChoseAnother() throws {
  let artifact = try shortlistFlower()
  let matches = try expandedMatches(artifact)
  let plain = CharacterShortlist(matches: matches, artifact: artifact, selectedCharacterID: nil)
  let led = CharacterShortlist(
    matches: matches, artifact: artifact, selectedCharacterID: nil, leadingCharacterID: "margaret")
  #expect(led.allMatches.first?.characterID == "margaret")
  #expect(led.selectedMatch?.characterID == "margaret")
  #expect(led.visibleMatches.first?.characterID == "margaret")
  // The rest keep their browsing order.
  #expect(
    led.allMatches.dropFirst().map(\.characterID)
      == plain.allMatches.map(\.characterID).filter { $0 != "margaret" })
  let manual = CharacterShortlist(
    matches: matches, artifact: artifact, selectedCharacterID: "ada",
    leadingCharacterID: "margaret")
  #expect(manual.selectedMatch?.characterID == "ada")
  let unknown = CharacterShortlist(
    matches: matches, artifact: artifact, selectedCharacterID: nil, leadingCharacterID: "nobody")
  #expect(unknown.allMatches.map(\.characterID) == plain.allMatches.map(\.characterID))
}

@Test func shortlistShowsDifferentArchetypesBeforeRepeatingOne() throws {
  let artifact = try Artifact(
    setName: "Golden Troupe", slot: .flower, main: .hp, level: 20,
    substats: [
      Substat(.critRate, 10.89), Substat(.critDamage, 21.76), Substat(.hpPercent, 9.91),
      Substat(.elementalMastery, 23.31),
    ])
  let matches = CharacterAssessment.evaluate(artifact)
  let shortlist = CharacterShortlist(matches: matches, artifact: artifact, selectedCharacterID: nil)
  let visible = shortlist.visibleMatches
  #expect(visible.count == 5)
  #expect(Set(visible.map(\.role.archetype)).count == 5)
  // Preferred-set roles still lead, and the reviewed role leads its archetype.
  #expect(visible.first?.setFit == .preferred)
  #expect(visible.contains { $0.characterID == "furina" })
}

@MainActor
@Test func shortlistLeadsWithTheVerdictsRoleAndKeepsOtherRoles() async throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  // An EM-heavy Obsidian Codex flower: Ifa's EM role keeps it, her ATK crit role grades it low.
  model.current = try Artifact(
    setName: "Obsidian Codex", slot: .flower, main: .hp, level: 20,
    substats: [
      Substat(.elementalMastery, 139.86), Substat(.critRate, 3.89), Substat(.critDamage, 7.77),
      Substat(.atk, 19.45),
    ])
  await model.evaluate()?.value
  let verdict = try #require(model.verdict)
  let shortlist = model.characterShortlist
  #expect(shortlist.selectedMatch?.roleID == verdict.roleID)
  #expect(shortlist.visibleMatches.first?.roleID == verdict.roleID)
  let ifa = shortlist.allMatches.filter { $0.characterID == "ifa" }.map(\.roleID)
  #expect(Set(ifa) == ["ifa.em", "ifa.atk-crit"])
  #expect(
    shortlist.label(try #require(shortlist.allMatches.first { $0.roleID == "ifa.em" })) != "Ifa")
  model.selectedCharacterID = "ifa"
  model.selectedRoleID = "ifa.atk-crit"
  #expect(model.selectedMatch?.roleID == "ifa.atk-crit")
  #expect(model.characterShortlist.visibleMatches.contains { $0.roleID == "ifa.atk-crit" })
}
