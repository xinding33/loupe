import CoreGraphics
import Foundation
import LoupeCore

struct LiveCardOCR {
  enum Pass: Equatable { case enhance, inventory }

  /// What Vision saw on a frame, before Enhance fields are confirmed across frames.
  private enum Observation {
    /// An Inventory card the parser can read.
    case inventory(CardReading)
    /// An Enhance panel, still to be confirmed.
    case enhance(heading: TextRegion?, regions: [TextRegion])
    /// The Enhance pass failed.
    case enhanceFailed(Error)
    /// Not Enhance, and no readable Inventory card: the Inventory read's result.
    case other(Result<CardReading, Error>)

    /// The passes a read of the same pixels would run after this one.
    var passesAgain: [Pass] {
      switch self {
      case .inventory: [.inventory]
      case .enhance, .enhanceFailed: [.enhance]
      case .other: [.enhance, .inventory]
      }
    }

    /// Whether reading the same pixels again would see the same. What we made of the frame
    /// would; a failure in Vision or in preparing the frame can be transient.
    var isRepeatable: Bool {
      switch self {
      case .inventory, .enhance: true
      case .enhanceFailed(let error): error is ArtifactError
      case .other(.success): true
      case .other(.failure(let error)): error is ArtifactError
      }
    }
  }

  private var confirmation = FieldConfirmation()
  private var size = CGSize.zero
  /// Whether the last frame was read as an Inventory card, so the next one tries that first.
  private var lastReadInventory = false
  /// The passes the last read ran, in order.
  private(set) var passes: [Pass] = []
  /// What the last read saw, while reading the same pixels again would see the same.
  private var observation: Observation?
  /// How many frames went through Vision.
  private(set) var visionReads = 0

  /// Whether `reread` can stand in for reading the last frame's pixels again.
  var canReread: Bool { observation != nil }

  mutating func read(
    _ image: CGImage, at time: TimeInterval, diagnostics: DiagnosticOCRTrace? = nil
  ) throws -> CardReading {
    let incoming = CGSize(width: image.width, height: image.height)
    if incoming != size { confirmation = FieldConfirmation() }
    size = incoming
    visionReads += 1
    let seen = observe(image, diagnostics: diagnostics)
    observation = seen.isRepeatable ? seen : nil
    return try apply(seen, at: time)
  }

  /// Reads the last frame's pixels again without Vision: the same outcome and state as `read`
  /// would give them at `time`. Enhance fields go through confirmation again.
  mutating func reread(at time: TimeInterval) throws -> CardReading {
    guard let observation else { throw ArtifactError("No frame to read again.") }
    passes = observation.passesAgain
    return try apply(observation, at: time)
  }

  /// Runs Vision. Its outcome is applied by `apply`, so `reread` repeats a read exactly.
  private mutating func observe(_ image: CGImage, diagnostics: DiagnosticOCRTrace?) -> Observation {
    passes = []
    // An Inventory card stays up for many frames, and reading it first skips the Enhance pass.
    // Anything short of a card falls back to the usual order, which reuses this result. An
    // Enhance title holds "/", which the Inventory read rejects.
    var inventory: (result: Result<CardReading, Error>, trace: DiagnosticOCRTrace?)?
    if lastReadInventory {
      let scratch = diagnostics.map { _ in DiagnosticOCRTrace() }
      let result = Result { try CardOCR.readInventory(image, diagnostics: scratch) }
      passes.append(.inventory)
      if let reading = try? result.get(), CardParser.parsedLines(reading.text) != nil {
        diagnostics?.mode = .inventory
        Self.adopt(scratch, into: diagnostics)
        return .inventory(reading)
      }
      inventory = (result, scratch)
    }
    passes.append(.enhance)
    let snapshot: (heading: TextRegion?, regions: [TextRegion])?
    do { snapshot = try CardOCR.enhancementSnapshot(image, diagnostics: diagnostics) } catch {
      return .enhanceFailed(error)
    }
    guard let snapshot else {
      diagnostics?.inputs = []
      diagnostics?.mode = .inventory
      let result: Result<CardReading, Error>
      if let inventory {
        Self.adopt(inventory.trace, into: diagnostics)
        result = inventory.result
      } else {
        passes.append(.inventory)
        result = Result { try CardOCR.readInventory(image, diagnostics: diagnostics) }
      }
      if let reading = try? result.get(), CardParser.parsedLines(reading.text) != nil {
        return .inventory(reading)
      }
      return .other(result)
    }
    diagnostics?.mode = .enhance
    return .enhance(heading: snapshot.heading, regions: snapshot.regions)
  }

  private mutating func apply(_ observation: Observation, at time: TimeInterval) throws
    -> CardReading
  {
    lastReadInventory = false
    switch observation {
    case .inventory(let reading):
      confirmation = FieldConfirmation()
      lastReadInventory = true
      return reading
    case .enhance(let heading, let regions):
      return try confirm((heading, regions), at: time)
    case .enhanceFailed(let error):
      throw error
    case .other(let result):
      confirmation = FieldConfirmation()
      return try result.get()
    }
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
