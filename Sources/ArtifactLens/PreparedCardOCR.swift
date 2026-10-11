import ArtifactCore
import CoreGraphics
import Foundation
import Vision

// Created only for opted-in reads and never passed across executors.
final class DiagnosticOCRTrace {
  var inputs: [DiagnosticInput] = []
  var mode: DiagnosticReadMode = .unknown
  var storageIssue: String?
}

enum PreparedCardOCR {
  static func configuration(correctWords: Bool) -> DiagnosticOCRConfiguration {
    DiagnosticOCRConfiguration(
      revision: Int(VNRecognizeTextRequest().revision), languages: ["en-US"], accurate: true,
      languageCorrection: correctWords, minimumTextHeight: 0.01)
  }

  static func recognize(_ image: CGImage, configuration: DiagnosticOCRConfiguration) throws
    -> [DiagnosticText]
  {
    let request = VNRecognizeTextRequest()
    request.revision = configuration.revision
    request.recognitionLevel = configuration.accurate ? .accurate : .fast
    request.recognitionLanguages = configuration.languages
    request.usesLanguageCorrection = configuration.languageCorrection
    request.minimumTextHeight = configuration.minimumTextHeight
    try VNImageRequestHandler(cgImage: image).perform([request])
    return (request.results ?? []).compactMap { observation in
      guard let candidate = observation.topCandidates(1).first else { return nil }
      return DiagnosticText(
        text: candidate.string, bounds: observation.boundingBox, confidence: candidate.confidence)
    }
  }

  static func regions(_ observations: [DiagnosticText], crop: CGRect, captureSize: CGSize)
    -> [TextRegion]
  {
    let area = CGRect(
      x: crop.minX / captureSize.width, y: 1 - crop.maxY / captureSize.height,
      width: crop.width / captureSize.width, height: crop.height / captureSize.height)
    return observations.map {
      TextRegion(
        text: $0.text,
        bounds: CGRect(
          x: area.minX + $0.bounds.minX * area.width, y: area.minY + $0.bounds.minY * area.height,
          width: $0.bounds.width * area.width, height: $0.bounds.height * area.height),
        confidence: $0.confidence)
    }
  }

  static func read(
    _ image: CGImage, crop: CGRect, captureSize: CGSize, kind: DiagnosticInputMetadata.Kind,
    correctWords: Bool, trace: DiagnosticOCRTrace?
  ) throws -> [TextRegion] {
    let configuration = configuration(correctWords: correctWords)
    var pixels: DiagnosticPixels?
    if let trace {
      do { pixels = try DiagnosticPixels(copying: image) } catch {
        trace.storageIssue = error.localizedDescription
      }
    }
    let input = try pixels?.makeImage() ?? image
    do {
      let observations = try recognize(input, configuration: configuration)
      if let pixels {
        trace?.inputs.append(
          DiagnosticInput(
            metadata: DiagnosticInputMetadata(
              kind: kind, cropBounds: crop, configuration: configuration,
              observations: observations, recognitionError: nil, isExactOCRInput: true),
            pixels: pixels))
      }
      return regions(observations, crop: crop, captureSize: captureSize)
    } catch {
      if let pixels {
        trace?.inputs.append(
          DiagnosticInput(
            metadata: DiagnosticInputMetadata(
              kind: kind, cropBounds: crop, configuration: configuration,
              observations: [], recognitionError: error.localizedDescription, isExactOCRInput: true),
            pixels: pixels))
      }
      throw error
    }
  }
}
