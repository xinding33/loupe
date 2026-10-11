import AppKit
import ArtifactCore
import Foundation
import SwiftUI
import Testing

@testable import ArtifactLens

private let assessmentFlower = """
  Dreaming Steelbloom
  Flower of Life
  HP
  4,780
  +20
  Elemental Mastery+117
  HP+5.8%
  CRIT Rate+7.8%
  DEF+23
  Gilded Dreams:
  """

@MainActor
@Test func assessmentUsesSelectedRoleWithoutChangingManualProfile() async throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  model.useText(assessmentFlower, confirmed: true)
  await model.evaluate()?.value
  let ids = model.characterMatches.map(\.characterID)
  #expect(ids.contains("alhaitham"))
  #expect(ids.contains("kuki-shinobu"))
  #expect(Set(ids).count == ids.count)
  #expect(model.selectedMatch?.characterID == "alhaitham")
  #expect(model.characterShortlist.visibleMatches.count <= 5)
  #expect(model.characterShortlist.visibleMatches.contains { $0.characterID == "alhaitham" })
  model.selectedCharacterID = "kuki-shinobu"
  let result = try #require(model.displayedPotential)
  #expect(result.currentScore == 5)
  #expect(model.selectedMatch?.grades?.current == .s)
  #expect(model.assessmentDescription.contains("Kuki Shinobu"))
  #expect(model.assessmentDescription.contains("experimental"))
  #expect(model.profileName == "Crit")
  model.assessmentMode = .profile
  #expect(model.displayedPotential?.currentScore == 2)
  #expect(model.assessmentDescription.contains("Crit"))
  model.assessmentMode = .characters
  #expect(model.displayedPotential?.currentScore == 5)
  #expect(model.inventory.artifacts.isEmpty)
}

@MainActor
@Test func assessmentDisableRejectsPendingCharacterResults() async throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  model.useText(assessmentFlower, confirmed: true)
  let pending = model.evaluate()
  model.setEnabled(false)
  await pending?.value
  #expect(model.characterMatches.isEmpty)
  #expect(model.displayedPotential == nil)
  #expect(model.current == nil)
}

@MainActor
@Test func assessmentMissingFourthKeepsFitButDoesNotInventOdds() async throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  model.useText(
    """
    Golden Goblet
    Goblet of Eonothem
    Hydro DMG Bonus
    7.0%
    +0
    HP+5.8%
    CRIT Rate+3.9%
    CRIT DMG+7.8%
    Golden Troupe:
    """, confirmed: true)
  await model.evaluate()?.value
  model.selectedCharacterID = "furina"
  #expect(model.current != nil)
  #expect(model.selectedMatch != nil)
  #expect(model.displayedPotential == nil)
  #expect(model.selectedMatch?.grades?.p50 == nil)
  #expect(model.evaluationIssue != nil)
  #expect(model.issue == nil)
}

@Test func characterDiagnosticUsesDisplayedRoleWeightsAndVersion() throws {
  let artifact = try CardParser.parse(assessmentFlower, fiveStarsConfirmed: true)
  let match = try #require(
    CharacterAssessment.evaluate(artifact).first { $0.characterID == "kuki-shinobu" })
  let result = try #require(match.potential)
  let evidence = DiagnosticRecommendation.evaluated(
    artifact, result: result, profile: match.profile, pool: [], scope: .offPiece,
    excluded: nil, match: match)
  #expect(evidence.weights == ["eleMas": 100])
  #expect(evidence.metrics["currentScore"] == 5)
  #expect(evidence.metrics["chanceOfAOrBetter"] == 1)
  #expect(evidence.dataVersion == CharacterAssessment.datasetVersion)
  #expect(evidence.scoringVersion.contains(CharacterAssessment.calibrationVersion))
  #expect(evidence.explanation.contains("experimental"))
}

@Test func upgradeGuidanceDoesNotSuggestImpossibleSubstatsOrRandomActivation() throws {
  let piece = try Artifact(
    setName: "Gilded Dreams", slot: .goblet, main: .elementalMastery, level: 0,
    substats: [Substat(.hpPercent, 5.8), Substat(.critRate, 3.9), Substat(.def, 23)],
    unactivated: Substat(.energyRecharge, 6.5))
  #expect(UpgradeGuidance.checkpoint(piece).contains("Energy Recharge"))
  #expect(UpgradeGuidance.checkpoint(piece).contains("fixed"))
  #expect(
    UpgradeGuidance.helpfulRolls(piece, usefulStats: [.elementalMastery]).hasPrefix(
      "No random roll"))
  #expect(
    !UpgradeGuidance.helpfulRolls(piece, usefulStats: [.elementalMastery]).contains(
      "Elemental Mastery"))
}

@Test func compactAccountComparisonRetainsScopeAndSavedCount() throws {
  let artifact = try CardParser.parse(assessmentFlower, fiveStarsConfirmed: true)
  let duplicate = try artifact.withID(UUID())
  let result = try Potential.evaluate(
    artifact, profile: Profile.presets[0], inventory: [duplicate], scope: .sameSet)
  let label = AccountSummary.label(result, scope: .sameSet, finished: true)
  #expect(label == "Beat saved best: No (same set, n=1)")
  #expect(AccountSummary.label(result, scope: .offPiece, finished: false).contains("all sets, n=1"))
}

/// Synthetic, private-data-free UI renders. Writes PNGs only when ARTIFACT_LENS_UI_PROOF is set.
@MainActor
@Test func renderSyntheticOverlayProofWhenRequested() async throws {
  guard let output = ProcessInfo.processInfo.environment["ARTIFACT_LENS_UI_PROOF"] else { return }
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
  let directory = URL(fileURLWithPath: output)

  func write(_ image: CGImage, _ name: String) throws {
    let data = try #require(
      NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
    try data.write(to: directory.appending(path: name), options: .withoutOverwriting)
  }
  func overlay(_ name: String, expanded: Bool) throws {
    model.overlayExpanded = expanded
    // Matches OverlayController: the 28-point control strip sits above the result surface.
    let renderer = ImageRenderer(
      content: OverlayView(model: model).frame(
        width: expanded ? 360 : 280, height: expanded ? 602 : 112))
    renderer.scale = 2
    try write(try #require(renderer.cgImage), name)
  }
  func dashboard(_ name: String) throws {
    let host = NSHostingView(rootView: Dashboard(model: model))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1080, height: 1000), styleMask: [.borderless],
      backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.contentView = host
    host.frame = window.contentLayoutRect
    host.layoutSubtreeIfNeeded()
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    try write(try #require(bitmap.cgImage), name)
  }
  func read(_ text: String) async {
    model.useText(text, confirmed: true)
    await model.evaluate()?.value
  }

  // Finished Kuki flower, no saved comparables.
  await read(assessmentFlower)
  model.selectedCharacterID = "kuki-shinobu"
  try overlay("compact.png", expanded: false)
  try overlay("expanded.png", expanded: true)

  // Unfinished Furina goblet compared with four synthetic saved +20 Hydro goblets.
  let saved: [[Substat]] = [
    [
      Substat(.hpPercent, 17.49), Substat(.critRate, 7.78), Substat(.critDamage, 14.76),
      Substat(.atk, 38.9),
    ],
    [
      Substat(.hpPercent, 23.32), Substat(.critRate, 5.83), Substat(.def, 46.3),
      Substat(.energyRecharge, 6.48),
    ],
    [
      Substat(.hpPercent, 19.81), Substat(.atk, 58.35), Substat(.def, 23.15),
      Substat(.energyRecharge, 6.48),
    ],
    [
      Substat(.hpPercent, 8.16), Substat(.atk, 77.8), Substat(.def, 46.3),
      Substat(.energyRecharge, 6.48),
    ],
  ]
  for (index, substats) in saved.enumerated() {
    model.inventory.save(
      try Artifact(
        setName: index == 0 ? "Golden Troupe" : "Nymph's Dream", slot: .goblet, main: .hydroDamage,
        level: 20, substats: substats))
  }
  await read(
    """
    Golden Goblet
    Goblet of Eonothem
    Hydro DMG Bonus
    7.0%
    +0
    HP+5.8%
    CRIT Rate+3.9%
    CRIT DMG+7.8%
    ATK+19
    Golden Troupe:
    """)
  model.selectedCharacterID = "furina"
  try overlay("goblet-compact.png", expanded: false)
  try overlay("goblet-expanded.png", expanded: true)
  try dashboard("dashboard-goblet.png")
  model.assessmentMode = .profile
  model.profileName = "HP + crit"
  await model.evaluate()?.value
  try dashboard("dashboard-profile.png")
  try overlay("profile-compact.png", expanded: false)
  model.assessmentMode = .characters

  // Missing preview line: fit remains, odds are withheld.
  await read(
    """
    Golden Goblet
    Goblet of Eonothem
    Hydro DMG Bonus
    7.0%
    +0
    HP+5.8%
    CRIT Rate+3.9%
    CRIT DMG+7.8%
    Golden Troupe:
    """)
  model.selectedCharacterID = "furina"
  try overlay("reread-compact.png", expanded: false)

  // EM sands: Kuki's only core stat is the main stat, so no scalar grade is shown.
  await read(
    """
    Dreaming Steelbloom
    Sands of Eon
    Elemental Mastery
    28
    +0
    HP+5.8%
    CRIT Rate+3.9%
    DEF+23
    Energy Recharge+6.5%
    Flower of Paradise Lost:
    """)
  model.selectedCharacterID = "kuki-shinobu"
  try overlay("em-sands-expanded.png", expanded: true)

  await read(
    """
    Dreaming Steelbloom
    Flower of Life
    HP
    717
    +0
    Elemental Mastery+23
    HP+5.8%
    CRIT Rate+3.9%
    DEF+23 (unactivated)
    Gilded Dreams:
    """)
  try overlay("starter-expanded.png", expanded: true)
  try dashboard("dashboard-starter.png")
  model.setEnabled(false)
  try overlay("waiting-compact.png", expanded: false)
}
