import CoreGraphics
import Foundation
import LoupeCore

struct LiveCardOCR {
  private var confirmation = FieldConfirmation()
  private var size = CGSize.zero

  mutating func read(
    _ image: CGImage, at time: TimeInterval, diagnostics: DiagnosticOCRTrace? = nil
  ) throws -> CardReading {
    let incoming = CGSize(width: image.width, height: image.height)
    if incoming != size { confirmation = FieldConfirmation() }
    size = incoming
    guard let snapshot = try CardOCR.enhancementSnapshot(image, diagnostics: diagnostics) else {
      confirmation = FieldConfirmation()
      diagnostics?.inputs = []
      diagnostics?.mode = .inventory
      return try CardOCR.readInventory(image, diagnostics: diagnostics)
    }
    diagnostics?.mode = .enhance
    return try confirm(snapshot, at: time)
  }

  mutating func replay(_ sample: DiagnosticSample) throws -> CardReading {
    let incoming = sample.metadata.captureSize
    if incoming != size || sample.metadata.resetsConfirmation { confirmation = FieldConfirmation() }
    size = incoming
    guard sample.metadata.mode == .enhance, sample.inputs.count == 2,
      let header = sample.inputs.first(where: { $0.metadata.kind == .enhanceHeading }),
      let stats = sample.inputs.first(where: { $0.metadata.kind == .enhanceStats }),
      sample.inputs.allSatisfy({ $0.metadata.isExactOCRInput })
    else {
      confirmation = FieldConfirmation()
      throw DiagnosticError.invalid(
        "partial or missing OCR inputs; Inventory full-window replay is unavailable")
    }
    func recognize(_ input: DiagnosticInput) throws -> [TextRegion] {
      let observations = try PreparedCardOCR.recognize(
        input.pixels.makeImage(), configuration: input.metadata.configuration)
      return PreparedCardOCR.regions(
        observations, crop: input.metadata.cropBounds, captureSize: incoming)
    }
    guard
      let snapshot = try CardOCR.enhancementSnapshot(
        header: recognize(header), regions: recognize(stats))
    else {
      confirmation = FieldConfirmation()
      throw DiagnosticError.invalid("replayed crops do not identify an Enhance table")
    }
    return try confirm(snapshot, at: sample.metadata.time)
  }

  private mutating func confirm(
    _ snapshot: (heading: TextRegion?, regions: [TextRegion]), at time: TimeInterval
  ) throws -> CardReading {
    let result = try confirmation.observe(snapshot.regions, heading: snapshot.heading, at: time)
    return CardReading(
      text: result.text, stars: 0, confidence: result.confidence, isEnhancement: true)
  }
}
