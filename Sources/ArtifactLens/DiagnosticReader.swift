import ArtifactCore
import CoreGraphics
import Foundation

struct DiagnosticCoverage: Sendable {
  let count: Int
  let duration: TimeInterval
  let imageBytes: Int
  let issue: String?
}

// Owned by FrameReader's existing serial OCR queue, including freeze and model callbacks.
struct DiagnosticReader {
  private var live = LiveCardOCR()
  private(set) var buffer: DiagnosticBuffer
  private var storageIssue: String?
  private var resetsConfirmation = true

  init(sessionID: UUID) throws { buffer = try DiagnosticBuffer(sessionID: sessionID) }

  var coverage: DiagnosticCoverage {
    DiagnosticCoverage(
      count: buffer.samples.count,
      duration: (buffer.samples.last?.metadata.time ?? 0)
        - (buffer.samples.first?.metadata.time ?? 0),
      imageBytes: buffer.samples.reduce(0) { $0 + $1.imageBytes }, issue: storageIssue)
  }

  mutating func setEnabled(_ value: Bool) { buffer.setEnabled(value) }
  mutating func resetOCR() {
    live = LiveCardOCR()
    resetsConfirmation = true
  }
  mutating func clear() {
    live = LiveCardOCR()
    resetsConfirmation = true
    buffer.setEnabled(false)
    storageIssue = nil
  }

  mutating func read(_ image: CGImage, at time: TimeInterval, capturedAt: Date = Date())
    -> (result: Result<CardReading, Error>, key: DiagnosticSampleKey?)
  {
    let trace = buffer.isEnabled ? DiagnosticOCRTrace() : nil
    let reset = resetsConfirmation
    resetsConfirmation = false
    let result = Result { try live.read(image, at: time, diagnostics: trace) }
    guard let trace else { return (result, nil) }
    let key = DiagnosticSampleKey(sessionID: buffer.sessionID, id: UUID(), time: time)
    let reading = try? result.get()
    let confirmation: String
    switch result {
    case .success:
      confirmation = trace.mode == .enhance ? "Fields confirmed" : "Inventory OCR assembled"
    case .failure(let error): confirmation = error.localizedDescription
    }
    let sample = DiagnosticSample(
      metadata: DiagnosticSampleMetadata(
        id: key.id, sessionID: key.sessionID, capturedAt: capturedAt, time: time,
        captureSize: CGSize(width: image.width, height: image.height),
        assembledText: reading?.text ?? "", parserDecision: "Awaiting model parsing",
        confirmationDecision: confirmation, parsedArtifact: nil, states: [], mode: trace.mode,
        readingConfidence: reading?.confidence, fiveStars: reading?.fiveStars,
        resetsConfirmation: reset),
      inputs: trace.mode == .unknown ? [] : trace.inputs)
    storageIssue = trace.storageIssue
    do {
      let admission = try buffer.append(sample)
      if admission == .oversized { storageIssue = DiagnosticError.oversized.localizedDescription }
      return (result, admission == .retained ? key : nil)
    } catch {
      storageIssue = error.localizedDescription
      return (result, nil)
    }
  }

  mutating func finish(
    _ key: DiagnosticSampleKey, artifact: Artifact?, decision: String, state: DiagnosticState
  ) {
    do { try buffer.finishReading(key, artifact: artifact, decision: decision, state: state) } catch
    { storageIssue = error.localizedDescription }
  }

  mutating func record(_ state: DiagnosticState, key: DiagnosticSampleKey) {
    do { try buffer.recordState(state, sampleID: key.id, sessionID: key.sessionID) } catch {
      storageIssue = error.localizedDescription
    }
  }

  mutating func expire(at time: TimeInterval) {
    do { try buffer.expire(at: time) } catch { storageIssue = error.localizedDescription }
  }
  mutating func freeze(at time: TimeInterval) throws -> DiagnosticSnapshot {
    try buffer.freeze(at: time)
  }
}

struct DiagnosticReplayContext: Sendable {
  var artifact: Artifact
  let pieceName: String
}

struct DiagnosticReplayResult {
  let sampleID: UUID
  let time: TimeInterval
  let reading: Result<CardReading, Error>
  let parsed: Result<Artifact, Error>
}

enum DiagnosticReplay {
  // Runs Vision again. Saved recognized text and user corrections are never replay inputs.
  static func run(_ report: DiagnosticReport, context: DiagnosticReplayContext?)
    -> [DiagnosticReplayResult]
  {
    var live = LiveCardOCR()
    var context = context
    return report.snapshot.samples.map { sample in
      let reading = Result { try live.replay(sample) }
      let parsed = Result {
        let value = try reading.get()
        guard let previous = context else {
          throw DiagnosticError.invalid("replay needs explicit verified Inventory context")
        }
        let artifact = try value.resolveEnhancement(
          previous: previous.artifact, pieceName: previous.pieceName)
        context?.artifact = artifact
        return artifact
      }
      return DiagnosticReplayResult(
        sampleID: sample.metadata.id, time: sample.metadata.time, reading: reading, parsed: parsed)
    }
  }
}
