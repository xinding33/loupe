import CoreImage
import CoreVideo
import Foundation
import LoupeCore

/// What one frame hands the model.
struct FrameDelivery {
  let result: Result<CardReading, Error>
  let key: DiagnosticSampleKey?
  let coverage: DiagnosticCoverage
}

/// Whether two deliveries say the same: the reading's text, stars and layout, or the error.
struct ReadingOutcome: Equatable {
  let text: String?
  let stars: Int
  let isEnhancement: Bool
  let error: String?

  init(_ result: Result<CardReading, Error>) {
    switch result {
    case .success(let reading):
      (text, stars, isEnhancement, error) = (
        reading.text, reading.stars, reading.isEnhancement, nil
      )
    case .failure(let failure):
      (text, stars, isEnhancement, error) = (nil, 0, false, failure.localizedDescription)
    }
  }
}

extension FrameSamples {
  /// Samples a BGRA capture buffer; nil for any other format or a buffer that can't be read, so
  /// the frame counts as changed.
  init?(_ buffer: CVPixelBuffer) {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
      !CVPixelBufferIsPlanar(buffer),
      CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess
    else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let height = CVPixelBufferGetHeight(buffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
    self.init(
      pixels: UnsafeRawBufferPointer(start: base, count: bytesPerRow * height),
      width: CVPixelBufferGetWidth(buffer), height: height, bytesPerRow: bytesPerRow)
  }
}

/// Reads, reuses or holds each captured frame; see `ReadPacing`. `FrameReader` drives it from the
/// capture stream, and tests drive it with pixel buffers and explicit times. Owned by the OCR
/// queue.
struct FramePipeline {
  var ocr: DiagnosticReader
  private var pacing = ReadPacing<ReadingOutcome>()
  /// The latest complete frame. Its image is copied out only when something needs it.
  private var screen: Screen?
  /// The samples of the frame last read.
  private var baseline: FrameSamples?
  private let context = CIContext()

  private struct Screen {
    var buffer: CVPixelBuffer?
    var image: CGImage?
    let samples: FrameSamples?
  }

  init(ocr: DiagnosticReader) { self.ocr = ocr }

  /// Whether an idle frame has a frame to repeat.
  var hasFrame: Bool { screen != nil }
  /// When a held frame must be read, if no frame comes first.
  var deadline: TimeInterval? { pacing.deadline }

  /// Takes a complete frame, before `complete` decides what to do with it, so a snapshot or a
  /// recording can have it first.
  mutating func show(_ buffer: CVPixelBuffer) {
    screen = Screen(buffer: buffer, image: nil, samples: FrameSamples(buffer))
  }

  /// The latest frame's image, copied from its buffer the first time it's asked for.
  mutating func image() -> CGImage? {
    guard var screen else { return nil }
    if screen.image == nil, let buffer = screen.buffer {
      let source = CIImage(cvPixelBuffer: buffer)
      screen.image = context.createCGImage(source, from: source.extent)
      // The copy stands in for the buffer, which can go back to the stream.
      if screen.image != nil { screen.buffer = nil }
      self.screen = screen
    }
    return screen.image
  }

  /// Decides for the frame `show` took.
  mutating func complete(at time: TimeInterval) -> FrameDelivery? {
    let unchanged =
      if let baseline, let samples = screen?.samples { !samples.differs(from: baseline) } else {
        false
      }
    return perform(pacing.frame(at: time, reusable: unchanged && ocr.canReuse), at: time)
  }

  /// A frame that repeats the one before it.
  mutating func idle(at time: TimeInterval) -> FrameDelivery? {
    perform(pacing.idle(at: time, reusable: baseline != nil && ocr.canReuse), at: time)
  }

  /// The timer at `deadline`.
  mutating func tick(at time: TimeInterval) -> FrameDelivery? {
    perform(pacing.tick(at: time), at: time)
  }

  /// Drops the frame, the last read and its outcome, as for a gap in the stream.
  mutating func reset() {
    screen = nil
    baseline = nil
    pacing = ReadPacing()
    ocr.resetOCR()
  }

  /// Reset, and the diagnostic buffer too, when capture ends.
  mutating func clear() {
    reset()
    ocr.clear()
    context.clearCaches()
  }

  private mutating func perform(
    _ decision: ReadPacing<ReadingOutcome>.Decision, at time: TimeInterval
  )
    -> FrameDelivery?
  {
    switch decision {
    case .read:
      guard let image = image() else {
        // Nothing to compare the next frame with, so it's read when due.
        screen = nil
        baseline = nil
        return nil
      }
      baseline = screen?.samples
      let output = ocr.read(image, at: time)
      return deliver(output.result, key: output.key)
    case .reuse:
      return deliver(ocr.reuse(at: time), key: nil)
    case .hold, .ignore:
      return nil
    }
  }

  private mutating func deliver(_ result: Result<CardReading, Error>, key: DiagnosticSampleKey?)
    -> FrameDelivery
  {
    pacing.delivered(ReadingOutcome(result))
    return FrameDelivery(result: result, key: key, coverage: ocr.coverage)
  }
}
