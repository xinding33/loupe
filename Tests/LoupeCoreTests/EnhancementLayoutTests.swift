import Foundation
import LoupeCore
import Testing

@Test func alignsSeparateColumnsEvenWhenInactiveTextWraps() throws {
  let text = try EnhancementLayout.assemble(regions, heading: heading).text
  #expect(text.contains("CRIT Rate+3.1% (unactivated)"))
  #expect(text.contains("CRIT DMG+6.2%"))
  #expect(!text.contains("CRIT DMG+6.2% (unactivated)"))
  #expect(text.contains("ATK+47"))
}

@Test func additionalPreviewValuesAndMissingRowsWithholdAdvice() {
  #expect(throws: ArtifactError.self) {
    try EnhancementLayout.assemble(regions + [region("59", 0.86, 0.73)], heading: heading)
  }
  #expect(throws: ArtifactError.self) {
    try EnhancementLayout.assemble(Array(regions.dropLast()), heading: heading)
  }
}

@Test(arguments: ["H\u{0420}", "\u{041D}P", "\u{041D}\u{0420}"])
func visuallyIdenticalHPLabelsProduceTheSameCard(_ label: String) throws {
  let expected = try EnhancementLayout.assemble(regions, heading: heading).text
  let observed = regions.map {
    $0.text == "HP"
      ? TextRegion(text: "\u{2022} " + label, bounds: $0.bounds, confidence: $0.confidence) : $0
  }
  let result = try EnhancementLayout.assemble(observed, heading: heading)
  #expect(result.text == expected)
  #expect(result.text.contains("HP+4.1%"))
}

@Test func unknownStatLabelStillWithholdsAdvice() {
  let observed = regions.map {
    $0.text == "HP"
      ? TextRegion(text: "HX", bounds: $0.bounds, confidence: $0.confidence) : $0
  }
  #expect(throws: ArtifactError.self) {
    try EnhancementLayout.assemble(observed, heading: heading)
  }
}

@Test func particlePunctuationDoesNotChangeStatMeaning() throws {
  let substitutions = [
    "+0": "✦+0-", "HP": "• HP*", "CRIT DMG": "ÇRIT-DMG",
    "4.1%": "- 4.1%-", "6.2%": "₩6.2%", "21": "21-",
  ]
  let observed = regions.map {
    TextRegion(
      text: substitutions[$0.text] ?? $0.text, bounds: $0.bounds, confidence: $0.confidence)
  }
  let expected = try EnhancementLayout.assemble(regions, heading: heading)
  let actual = try EnhancementLayout.assemble(observed, heading: heading)
  #expect(actual.text == expected.text)
  #expect(actual.confidence == expected.confidence)
}

@Test(arguments: ["4..1%", "4.1% 5.8%", "4.l%", "4.1%%", "4 1%", "4.1% -> 5.8%"])
func ambiguousNumbersAreNotRepaired(_ value: String) {
  let observed = regions.map {
    TextRegion(
      text: $0.text == "4.1%" ? value : $0.text, bounds: $0.bounds, confidence: $0.confidence)
  }
  #expect(throws: ArtifactError.self) { try EnhancementLayout.assemble(observed, heading: heading) }
}

private let heading = region("Plume of Death / Feather of Indelible Sin", 0.07, 0.90)
private let regions = [
  region("+0", 0.6, 0.81),
  region("✦ ATK", 0.6, 0.73), region("47", 0.94, 0.73),
  region("DEF", 0.6, 0.67), region("21", 0.94, 0.67),
  region("HP", 0.6, 0.63), region("4.1%", 0.94, 0.63),
  region("CRIT DMG", 0.6, 0.59), region("6.2%", 0.94, 0.59),
  region("CRIT Rate (unactivated)", 0.6, 0.54, height: 0.037), region("3.1%", 0.94, 0.555),
]

private func region(_ text: String, _ x: Double, _ y: Double, height: Double = 0.015) -> TextRegion
{
  TextRegion(text: text, bounds: CGRect(x: x, y: y, width: 0.05, height: height), confidence: 1)
}
