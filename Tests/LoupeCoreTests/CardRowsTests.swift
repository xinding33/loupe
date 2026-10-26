import Foundation
import LoupeCore
import Testing

private func region(_ text: String, _ x: Double, _ y: Double, width: Double) -> TextRegion {
  TextRegion(text: text, bounds: CGRect(x: x, y: y, width: width, height: 0.02), confidence: 1)
}

@Test func aSubstatSplitWithinItsRowIsJoined() {
  // Live character screen: Vision returned "CRIT" and "DMG+12.4%" as two observations.
  let rows = CardRows.joined([
    region("DMG+12.4%", 0.811, 0.616, width: 0.07), region("CRIT", 0.775, 0.621, width: 0.03),
    region("• HP+8.2%", 0.764, 0.646, width: 0.06),
  ])
  #expect(rows.map(\.text) == ["• HP+8.2%", "CRIT DMG+12.4%"])
}

@Test func aMainStatValueStaysItsOwnLine() {
  // The value sits at the far edge beside "HP", but right after a long label such as
  // "Hydro DMG Bonus"; the reader finds the stars by the value's own line.
  let rows = CardRows.joined([
    region("HP", 0.767, 0.771, width: 0.02), region("717", 0.942, 0.769, width: 0.03),
    region("Hydro DMG Bonus", 0.763, 0.700, width: 0.1), region("46.6%", 0.865, 0.700, width: 0.04),
  ])
  #expect(rows.map(\.text).sorted() == ["46.6%", "717", "HP", "Hydro DMG Bonus"])
}
