import ArtifactCore
import Testing

@testable import ArtifactLens

@Test func uncertainEnhanceReadingCanOnlyConfirmAnExactVerifiedCard() throws {
  let previous = try Artifact(
    setName: "Night of the Sky's Unveiling", slot: .plume, main: .atk, level: 0,
    substats: [Substat(.def, 21), Substat(.hpPercent, 4.1), Substat(.critDamage, 6.2)],
    unactivated: Substat(.critRate, 3.1))
  let text = """
    Plume of Death / Feather of Indelible Sin
    +0
    ATK+47
    DEF+21
    HP+4.1%
    CRIT DMG+6.2%
    CRIT Rate+3.1% (unactivated)
    """
  let reading = CardReading(text: text, fiveStars: false, confidence: 0.5, isEnhancement: true)
  let actual = try reading.resolveEnhancement(
    previous: previous, pieceName: "Feather of Indelible Sin")
  #expect(actual.signature == previous.signature)

  let upgraded = text.replacingOccurrences(of: "+0\n", with: "+4\n")
    .replacingOccurrences(of: " (unactivated)", with: "")
  let uncertainChange = CardReading(
    text: upgraded, fiveStars: false, confidence: 0.5, isEnhancement: true)
  #expect(throws: ArtifactError.self) {
    try uncertainChange.resolveEnhancement(
      previous: previous, pieceName: "Feather of Indelible Sin")
  }
  let confidentChange = CardReading(
    text: upgraded, fiveStars: false, confidence: 1, isEnhancement: true)
  let changed = try confidentChange.resolveEnhancement(
    previous: previous, pieceName: "Feather of Indelible Sin")
  #expect(changed.level == 4)
  #expect(changed.substats.count == 4)
  #expect(changed.unactivated == nil)

  let unreadable = CardReading(text: text, fiveStars: false, confidence: 0.49, isEnhancement: true)
  #expect(throws: ArtifactError.self) {
    try unreadable.resolveEnhancement(previous: previous, pieceName: "Feather of Indelible Sin")
  }
  #expect(throws: ArtifactError.self) {
    try reading.resolveEnhancement(previous: previous, pieceName: "Another artifact")
  }
  let wrong = CardReading(
    text: text.replacingOccurrences(of: "DEF+21", with: "DEF+23"), fiveStars: false, confidence: 1,
    isEnhancement: true)
  #expect(throws: ArtifactError.self) {
    try wrong.resolveEnhancement(previous: previous, pieceName: "Feather of Indelible Sin")
  }
  let missingInactive = CardReading(
    text: text.replacingOccurrences(of: " (unactivated)", with: ""), fiveStars: false,
    confidence: 1, isEnhancement: true)
  #expect(throws: ArtifactError.self) {
    try missingInactive.resolveEnhancement(
      previous: previous, pieceName: "Feather of Indelible Sin")
  }
}
