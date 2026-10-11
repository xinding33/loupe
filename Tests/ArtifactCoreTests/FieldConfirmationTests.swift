import ArtifactCore
import Foundation
import Testing

@Test func separateFieldDropoutsKeepAConfirmedCardButOldEvidenceExpires() throws {
  var reader = FieldConfirmation()
  #expect(throws: ArtifactError.self) { try reader.observe(fields, heading: title, at: 0) }
  let initial = try reader.observe(fields, heading: title, at: 0.5)
  let missingValue = fields.filter { $0.text != "4.1%" }
  let first = try reader.observe(missingValue, heading: nil, at: 1)
  #expect(first.text == initial.text)
  let missingLabel = fields.filter { $0.text != "DEF" }
  let second = try reader.observe(missingLabel, heading: title, at: 1.5)
  #expect(second.text == initial.text)
  #expect(throws: ArtifactError.self) { try reader.observe([], heading: nil, at: 4) }
  #expect(throws: ArtifactError.self) { try reader.observe(fields, heading: title, at: 4.5) }
  let recovered = try reader.observe(fields, heading: title, at: 5)
  #expect(recovered.text == initial.text)
}

@Test func aChangedValueNeedsTwoFreshObservations() throws {
  var reader = FieldConfirmation()
  #expect(throws: ArtifactError.self) { try reader.observe(fields, heading: title, at: 0) }
  _ = try reader.observe(fields, heading: title, at: 0.5)
  let changed = fields.map { region in
    TextRegion(
      text: region.text == "6.2%" ? "12.4%" : region.text, bounds: region.bounds,
      confidence: region.confidence)
  }
  #expect(throws: ArtifactError.self) { try reader.observe(changed, heading: title, at: 1) }
  let confirmed = try reader.observe(changed, heading: title, at: 1.5)
  #expect(confirmed.text.contains("CRIT DMG+12.4%"))
  #expect(!confirmed.text.contains("CRIT DMG+6.2%"))
}

@Test func levelChangeStartsNewEvidenceAndDoesNotCarryInactiveTextForward() throws {
  var reader = FieldConfirmation()
  #expect(throws: ArtifactError.self) { try reader.observe(fields, heading: title, at: 0) }
  _ = try reader.observe(fields, heading: title, at: 0.5)
  let upgraded = fields.map { region in
    TextRegion(
      text: region.text.replacingOccurrences(of: "+0", with: "+4").replacingOccurrences(
        of: " (unactivated)", with: ""), bounds: region.bounds, confidence: region.confidence)
  }
  #expect(throws: ArtifactError.self) { try reader.observe(upgraded, heading: title, at: 1) }
  let confirmed = try reader.observe(upgraded, heading: title, at: 1.5)
  #expect(confirmed.text.contains("\n+4\n"))
  #expect(!confirmed.text.contains("unactivated"))
}

@Test func aPreviewCannotChooseOneOfTwoConflictingValues() throws {
  var reader = FieldConfirmation()
  #expect(throws: ArtifactError.self) { try reader.observe(fields, heading: title, at: 0) }
  _ = try reader.observe(fields, heading: title, at: 0.5)
  let preview = fields + [region("59", 0.96, 0.73)]
  #expect(throws: ArtifactError.self) { try reader.observe(preview, heading: title, at: 1) }
  #expect(throws: ArtifactError.self) { try reader.observe(preview, heading: title, at: 1.5) }
}

private let title = region("Plume of Death / Feather of Indelible Sin", 0.07, 0.90)
private let fields = [
  region("+0", 0.6, 0.81),
  region("ATK", 0.6, 0.73), region("47", 0.94, 0.73),
  region("DEF", 0.6, 0.67), region("21", 0.94, 0.67),
  region("HP", 0.6, 0.63), region("4.1%", 0.94, 0.63),
  region("CRIT DMG", 0.6, 0.59), region("6.2%", 0.94, 0.59),
  region("CRIT Rate (unactivated)", 0.6, 0.55), region("3.1%", 0.94, 0.55),
]

private func region(_ text: String, _ x: Double, _ y: Double) -> TextRegion {
  TextRegion(text: text, bounds: CGRect(x: x, y: y, width: 0.05, height: 0.015), confidence: 1)
}
