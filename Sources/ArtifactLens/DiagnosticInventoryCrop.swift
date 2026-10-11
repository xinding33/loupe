import CoreGraphics
import Foundation
import Vision

extension CardOCR {
  // Reuse the existing anchor-selected observations; do not run another detector or Vision request.
  static func recordInventoryCrop(
    _ image: CGImage, card: [VNRecognizedTextObservation], trace: DiagnosticOCRTrace
  ) {
    guard let first = card.first else { return }
    let bounds = card.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
    let frame = CGRect(x: 0, y: 0, width: image.width, height: image.height)
    let rect = CGRect(
      x: bounds.minX * frame.width, y: (1 - bounds.maxY) * frame.height,
      width: bounds.width * frame.width, height: bounds.height * frame.height
    ).integral.intersection(frame)
    guard rect != frame, !rect.isEmpty, let crop = image.cropping(to: rect) else { return }
    do {
      let pixels = try DiagnosticPixels(copying: crop)
      let observations = card.compactMap { observation -> DiagnosticText? in
        guard let candidate = observation.topCandidates(1).first else { return nil }
        let box = observation.boundingBox
        let local = CGRect(
          x: (box.minX * frame.width - rect.minX) / rect.width,
          y: (box.minY * frame.height - (frame.height - rect.maxY)) / rect.height,
          width: box.width * frame.width / rect.width,
          height: box.height * frame.height / rect.height
        ).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !local.isEmpty else { return nil }
        return DiagnosticText(
          text: candidate.string, bounds: local, confidence: candidate.confidence)
      }
      trace.inputs = [
        DiagnosticInput(
          metadata: DiagnosticInputMetadata(
            kind: .inventoryCard, cropBounds: rect,
            configuration: PreparedCardOCR.configuration(correctWords: false),
            observations: observations, recognitionError: nil, isExactOCRInput: false),
          pixels: pixels)
      ]
    } catch { trace.storageIssue = error.localizedDescription }
  }
}
