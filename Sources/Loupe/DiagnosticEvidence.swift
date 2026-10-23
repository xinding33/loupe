import CoreGraphics
import Foundation
import LoupeCore

enum DiagnosticError: LocalizedError {
  case invalid(String)
  case oversized
  case saveInProgress

  var errorDescription: String? {
    switch self {
    case .invalid(let reason): "Invalid diagnostic evidence: \(reason)"
    case .oversized: "Diagnostic evidence exceeds the memory budget."
    case .saveInProgress: "A diagnostic report is already being saved."
    }
  }
}

// Raw, tightly packed sRGB RGBA8 pixels. No CGImage or crop backing store is retained.
struct DiagnosticPixels: Sendable {
  static let byteLimit = 24 * 1024 * 1024
  let width: Int
  let height: Int
  let bytes: Data
  private static let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
    CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))

  static func byteCount(width: Int, height: Int) throws -> Int {
    guard width > 0, height > 0, width <= byteLimit / 4,
      height <= byteLimit / (width * 4)
    else { throw DiagnosticError.oversized }
    return width * height * 4
  }

  init(width: Int, height: Int, bytes: Data) throws {
    guard bytes.count == (try Self.byteCount(width: width, height: height)) else {
      throw DiagnosticError.invalid("pixel byte count")
    }
    self.width = width
    self.height = height
    // Data slices and bridged NSData can retain a larger allocation.
    self.bytes = bytes.withUnsafeBytes { Data($0) }
  }

  init(copying crop: CGImage) throws {
    width = crop.width
    height = crop.height
    var storage = Data(count: try Self.byteCount(width: width, height: height))
    try storage.withUnsafeMutableBytes { buffer in
      guard let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
          data: buffer.baseAddress, width: crop.width, height: crop.height,
          bitsPerComponent: 8, bytesPerRow: crop.width * 4, space: space,
          bitmapInfo: Self.bitmapInfo.rawValue)
      else { throw DiagnosticError.invalid("cannot allocate crop pixels") }
      context.setBlendMode(.copy)
      context.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
    }
    bytes = storage
  }

  func makeImage() throws -> CGImage {
    guard let provider = CGDataProvider(data: bytes as CFData),
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
        bytesPerRow: width * 4, space: space, bitmapInfo: Self.bitmapInfo,
        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    else { throw DiagnosticError.invalid("cannot reconstruct crop") }
    return image
  }
}

struct DiagnosticOCRConfiguration: Codable, Sendable {
  let revision: Int
  let languages: [String]
  let accurate: Bool
  let languageCorrection: Bool
  let minimumTextHeight: Float
}

struct DiagnosticText: Codable, Sendable {
  let text: String
  // Vision normalized coordinates within the prepared input, bottom-left origin.
  let bounds: CGRect
  let confidence: Float
}

struct DiagnosticInputMetadata: Codable, Sendable {
  enum Kind: String, Codable { case inventoryCard, enhanceHeading, enhanceStats }
  let kind: Kind
  // Pixel coordinates in the captured window, top-left origin, before resizing.
  let cropBounds: CGRect
  let configuration: DiagnosticOCRConfiguration
  let observations: [DiagnosticText]
  let recognitionError: String?
  var isExactOCRInput = false
}

struct DiagnosticInput: Sendable {
  let metadata: DiagnosticInputMetadata
  let pixels: DiagnosticPixels
}

struct DiagnosticPlacement: Codable, Sendable, Equatable {
  // Global AppKit points, bottom-left origin. No display images or names.
  let window: CGRect
  let displays: [CGRect]
  let selectedDisplay: Int?
  let overlay: CGRect
  let scale: Double
}

struct DiagnosticRecommendation: Codable, Sendable {
  let scoringVersion: String
  let dataVersion: String
  let profile: String
  let scope: String
  let weights: [String: Double]
  let comparisonPieces: [Artifact]
  let excludedID: UUID?
  let metrics: [String: Double]
  let explanation: String
}

struct DiagnosticState: Codable, Sendable {
  let time: TimeInterval
  // Can refer to an older, evicted sample when the UI still shows its result.
  let displayedSampleID: UUID?
  let readingState: String
  let displayedText: String
  let recommendation: DiagnosticRecommendation?
  let placement: DiagnosticPlacement?
}

struct DiagnosticSampleMetadata: Codable, Sendable {
  let id: UUID
  let sessionID: UUID
  let capturedAt: Date
  // The same monotonic/session-relative time passed to confirmation during live reading.
  let time: TimeInterval
  let captureSize: CGSize
  let assembledText: String
  var parserDecision: String
  let confirmationDecision: String
  var parsedArtifact: Artifact?
  var states: [DiagnosticState]
  var mode: DiagnosticReadMode = .unknown
  var readingConfidence: Float?
  var fiveStars: Bool?
  var resetsConfirmation = false
}

enum DiagnosticReadMode: String, Codable, Sendable { case unknown, inventory, enhance }

struct DiagnosticSampleKey: Sendable, Equatable {
  let sessionID: UUID
  let id: UUID
  let time: TimeInterval
}

struct DiagnosticSample: Sendable {
  var metadata: DiagnosticSampleMetadata
  let inputs: [DiagnosticInput]

  var imageBytes: Int { inputs.reduce(0) { $0 + $1.pixels.bytes.count } }

  // Charge metadata as well as images so repeated failures and equal timestamps stay bounded.
  // This is an accounting budget, not a measurement of Swift allocator overhead.
  var retainedCost: Int {
    var cost =
      1024 + imageBytes + metadata.assembledText.utf8.count
      + metadata.parserDecision.utf8.count + metadata.confirmationDecision.utf8.count
      + artifactCost(metadata.parsedArtifact)
    for input in inputs {
      cost += 512 + (input.metadata.recognitionError?.utf8.count ?? 0)
      cost += input.metadata.configuration.languages.reduce(0) { $0 + 64 + $1.utf8.count }
      cost += input.metadata.observations.reduce(0) { $0 + 128 + $1.text.utf8.count }
    }
    for state in metadata.states {
      cost += 512 + state.readingState.utf8.count + state.displayedText.utf8.count
      cost += (state.placement?.displays.count ?? 0) * 64
      if let recommendation = state.recommendation {
        cost +=
          512 + recommendation.scoringVersion.utf8.count
          + recommendation.dataVersion.utf8.count + recommendation.profile.utf8.count
          + recommendation.scope.utf8.count + recommendation.explanation.utf8.count
        cost += recommendation.comparisonPieces.reduce(0) { $0 + artifactCost($1) }
        cost += recommendation.metrics.keys.reduce(0) { $0 + 128 + $1.utf8.count }
        cost += recommendation.weights.keys.reduce(0) { $0 + 128 + $1.utf8.count }
      }
    }
    return cost
  }

  private func artifactCost(_ artifact: Artifact?) -> Int {
    guard let artifact else { return 0 }
    return 512 + artifact.setName.utf8.count + artifact.substats.count * 64
  }

  func checked() throws -> Self {
    guard metadata.time.isFinite, metadata.capturedAt.timeIntervalSince1970.isFinite,
      metadata.captureSize.width.isFinite, metadata.captureSize.height.isFinite,
      metadata.captureSize.width > 0, metadata.captureSize.height > 0
    else { throw DiagnosticError.invalid("sample time or capture size") }
    guard metadata.readingConfidence.map({ $0.isFinite && (0...1).contains($0) }) ?? true else {
      throw DiagnosticError.invalid("reading confidence")
    }
    let capture = CGRect(origin: .zero, size: metadata.captureSize)
    for input in inputs {
      let value = input.metadata
      guard value.kind != .inventoryCard || !value.isExactOCRInput else {
        throw DiagnosticError.invalid("Inventory crop is not an exact full-window OCR input")
      }
      guard Self.validRect(value.cropBounds), capture.contains(value.cropBounds),
        value.cropBounds != capture,
        value.configuration.revision > 0, !value.configuration.languages.isEmpty,
        value.configuration.minimumTextHeight.isFinite,
        (0...1).contains(value.configuration.minimumTextHeight)
      else { throw DiagnosticError.invalid("crop or OCR configuration") }
      for observation in value.observations {
        // Vision estimates can cross an image edge. Preserve them rather than clipping evidence.
        guard Self.validRect(observation.bounds),
          observation.confidence.isFinite, (0...1).contains(observation.confidence)
        else {
          throw DiagnosticError.invalid(
            "OCR observation bounds \(observation.bounds), confidence \(observation.confidence)")
        }
      }
    }
    var previous = metadata.time
    for state in metadata.states {
      guard state.time.isFinite, state.time >= previous else {
        throw DiagnosticError.invalid("state timing")
      }
      previous = state.time
      if let placement = state.placement {
        guard Self.validRect(placement.window), Self.validRect(placement.overlay),
          placement.displays.allSatisfy(Self.validRect), placement.scale.isFinite,
          placement.scale > 0,
          placement.selectedDisplay.map({ placement.displays.indices.contains($0) }) ?? true
        else { throw DiagnosticError.invalid("placement geometry") }
      }
      if let recommendation = state.recommendation {
        guard recommendation.weights.values.allSatisfy(\.isFinite),
          recommendation.metrics.values.allSatisfy(\.isFinite)
        else { throw DiagnosticError.invalid("recommendation numbers") }
      }
    }
    return self
  }

  private static func validRect(_ rect: CGRect) -> Bool {
    rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite
      && rect.height.isFinite && rect.width > 0 && rect.height > 0
  }
}
