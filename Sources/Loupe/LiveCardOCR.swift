import CoreGraphics
import Foundation
import LoupeCore

struct LiveCardOCR {
  enum Pass: Equatable { case enhance, inventory }

  private var confirmation = FieldConfirmation()
  private var size = CGSize.zero
  /// Whether the last frame was read as an Inventory card, so the next one tries that first.
  private var lastReadInventory = false
  /// The passes the last read ran, in order.
  private(set) var passes: [Pass] = []

  mutating func read(
    _ image: CGImage, at time: TimeInterval, diagnostics: DiagnosticOCRTrace? = nil
  ) throws -> CardReading {
    let incoming = CGSize(width: image.width, height: image.height)
    if incoming != size { confirmation = FieldConfirmation() }
    size = incoming
    passes = []
    let triesInventoryFirst = lastReadInventory
    lastReadInventory = false
    // An Inventory card stays up for many frames, and reading it first skips the Enhance pass.
    // Anything short of a card falls back to the usual order, which reuses this result. An
    // Enhance title holds "/", which the Inventory read rejects.
    var inventory: (result: Result<CardReading, Error>, trace: DiagnosticOCRTrace?)?
    if triesInventoryFirst {
      let scratch = diagnostics.map { _ in DiagnosticOCRTrace() }
      let result = Result { try CardOCR.readInventory(image, diagnostics: scratch) }
      passes.append(.inventory)
      if let reading = try? result.get(), CardParser.parsedLines(reading.text) != nil {
        confirmation = FieldConfirmation()
        diagnostics?.mode = .inventory
        Self.adopt(scratch, into: diagnostics)
        lastReadInventory = true
        return reading
      }
      inventory = (result, scratch)
    }
    passes.append(.enhance)
    guard let snapshot = try CardOCR.enhancementSnapshot(image, diagnostics: diagnostics) else {
      confirmation = FieldConfirmation()
      diagnostics?.inputs = []
      diagnostics?.mode = .inventory
      let reading: CardReading
      if let inventory {
        Self.adopt(inventory.trace, into: diagnostics)
        reading = try inventory.result.get()
      } else {
        passes.append(.inventory)
        reading = try CardOCR.readInventory(image, diagnostics: diagnostics)
      }
      lastReadInventory = CardParser.parsedLines(reading.text) != nil
      return reading
    }
    diagnostics?.mode = .enhance
    return try confirm(snapshot, at: time)
  }

  /// Takes what an Inventory read recorded on a scratch trace, as if it had recorded on `trace`.
  private static func adopt(_ scratch: DiagnosticOCRTrace?, into trace: DiagnosticOCRTrace?) {
    guard let scratch, let trace else { return }
    trace.inputs = scratch.inputs
    if let issue = scratch.storageIssue { trace.storageIssue = issue }
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
