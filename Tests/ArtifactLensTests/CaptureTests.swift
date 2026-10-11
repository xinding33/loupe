import AppKit
import ArtifactCore
import Testing

@testable import ArtifactLens

@MainActor
@Test(arguments: [1, 2])
func readsEnhanceStatCropWithDimmedInactiveRow(_ scale: Int) throws {
  let context = try #require(
    CGContext(
      data: nil, width: 1152 * scale, height: 768 * scale, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  )
  context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
  context.setFillColor(NSColor(calibratedRed: 0.28, green: 0.20, blue: 0.14, alpha: 1).cgColor)
  context.fill(CGRect(x: 0, y: 0, width: 1152, height: 768))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  defer { NSGraphicsContext.restoreGraphicsState() }
  func draw(_ text: String, _ x: Double, _ y: Double, dim: Bool = false) {
    (text as NSString).draw(
      at: NSPoint(x: x, y: y),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
        .foregroundColor: dim ? NSColor.lightGray : NSColor.white,
      ])
  }
  draw("Plume of Death / Feather of Indelible Sin", 85, 710)
  draw("+0", 705, 640)
  draw("ATK", 720, 580)
  draw("47", 1090, 580)
  draw("HP", 720, 535)
  draw("209", 1090, 535)
  draw("DEF", 720, 503)
  draw("16", 1090, 503)
  draw("Elemental Mastery", 720, 471)
  draw("19", 1090, 471)
  draw("CRIT DMG", 720, 438, dim: true)
  draw("(unactivated)", 720, 419, dim: true)
  draw("6.2%", 1080, 438, dim: true)

  let image = try #require(context.makeImage())
  let reading = try CardOCR.read(image)
  #expect(reading.isEnhancement)
  #expect(reading.confidence >= 0.65)
  let previous = try Artifact(
    setName: "Night of the Sky's Unveiling", slot: .plume, main: .atk, level: 0,
    substats: [Substat(.hp, 209), Substat(.def, 16), Substat(.elementalMastery, 19)],
    unactivated: Substat(.critDamage, 6.2))
  let parsed = try CardParser.parseEnhancement(
    reading.text, previous: previous, pieceName: "Feather of Indelible Sin")
  #expect(parsed.signature == previous.signature)

}
