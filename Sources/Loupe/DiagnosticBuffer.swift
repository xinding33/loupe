import Foundation
import LoupeCore

struct DiagnosticSnapshot: Sendable {
  let sessionID: UUID
  let frozenAt: TimeInterval
  let samples: [DiagnosticSample]
  let evictedSamples: Int
  let oversizedSamples: Int

  var retainedDuration: TimeInterval {
    guard let first = samples.first, let last = samples.last else { return 0 }
    return last.metadata.time - first.metadata.time
  }
  var imageBytes: Int { samples.reduce(0) { $0 + $1.imageBytes } }
}

// Keep on the runtime owner's serial executor. This type schedules no work and performs no IO.
struct DiagnosticBuffer: Sendable {
  enum Admission: Equatable { case retained, disabled, wrongSession, outOfOrder, oversized }
  private(set) var sessionID: UUID
  private(set) var isEnabled = false
  private(set) var samples: [DiagnosticSample] = []
  private(set) var retainedCost = 0
  private var lastTime: TimeInterval?
  private var evictedSamples = 0
  private var oversizedSamples = 0
  let duration: TimeInterval
  let byteLimit: Int

  init(
    sessionID: UUID, duration: TimeInterval = 10, byteLimit: Int = DiagnosticPixels.byteLimit
  ) throws {
    guard duration.isFinite, duration > 0, duration <= 10,
      byteLimit > 0, byteLimit <= DiagnosticPixels.byteLimit
    else { throw DiagnosticError.invalid("buffer limits") }
    self.sessionID = sessionID
    self.duration = duration
    self.byteLimit = byteLimit
  }

  mutating func setEnabled(_ enabled: Bool) {
    if !enabled { clear() }
    isEnabled = enabled
  }

  mutating func beginSession(_ sessionID: UUID) {
    clear()
    self.sessionID = sessionID
  }

  mutating func clear() {
    samples = []
    retainedCost = 0
    lastTime = nil
    evictedSamples = 0
    oversizedSamples = 0
  }

  mutating func append(_ sample: DiagnosticSample) throws -> Admission {
    guard isEnabled else { return .disabled }
    guard sample.metadata.sessionID == sessionID else { return .wrongSession }
    let sample = try sample.checked()
    guard lastTime.map({ sample.metadata.time >= $0 }) ?? true else { return .outOfOrder }
    guard !samples.contains(where: { $0.metadata.id == sample.metadata.id }) else {
      throw DiagnosticError.invalid("duplicate sample identity")
    }
    lastTime = sample.metadata.time
    evict(at: sample.metadata.time)
    let cost = sample.retainedCost
    guard cost <= byteLimit else {
      oversizedSamples += 1
      return .oversized
    }
    samples.append(sample)
    retainedCost += cost
    evict(at: sample.metadata.time)
    return .retained
  }

  // Attach asynchronous evaluation and display transitions to the triggering OCR sample.
  @discardableResult
  mutating func recordState(_ state: DiagnosticState, sampleID: UUID, sessionID: UUID) throws
    -> Bool
  {
    guard isEnabled, sessionID == self.sessionID,
      let index = samples.firstIndex(where: { $0.metadata.id == sampleID })
    else { return false }
    var sample = samples[index]
    sample.metadata.states.append(state)
    try replace(sample, at: index, time: state.time)
    return samples.contains { $0.metadata.id == sampleID }
  }

  mutating func finishReading(
    _ key: DiagnosticSampleKey, artifact: Artifact?, decision: String, state: DiagnosticState
  ) throws {
    guard isEnabled, key.sessionID == sessionID,
      let index = samples.firstIndex(where: { $0.metadata.id == key.id })
    else { return }
    var sample = samples[index]
    sample.metadata.parsedArtifact = artifact
    sample.metadata.parserDecision = decision
    sample.metadata.states.append(state)
    try replace(sample, at: index, time: state.time)
  }

  private mutating func replace(_ sample: DiagnosticSample, at index: Int, time: TimeInterval)
    throws
  {
    let sample = try sample.checked()
    retainedCost += sample.retainedCost - samples[index].retainedCost
    samples[index] = sample
    let time = max(lastTime ?? time, time)
    lastTime = time
    evict(at: time)
  }

  mutating func expire(at time: TimeInterval) throws {
    guard time.isFinite, lastTime.map({ time >= $0 }) ?? true else {
      throw DiagnosticError.invalid("buffer clock moved backwards")
    }
    lastTime = time
    evict(at: time)
  }

  // Transfer evidence to one preview and pause collection until its owner explicitly resumes.
  mutating func freeze(at time: TimeInterval) throws -> DiagnosticSnapshot {
    try expire(at: time)
    let snapshot = DiagnosticSnapshot(
      sessionID: sessionID, frozenAt: time, samples: samples,
      evictedSamples: evictedSamples, oversizedSamples: oversizedSamples)
    setEnabled(false)
    return snapshot
  }

  private mutating func evict(at time: TimeInterval) {
    while let first = samples.first,
      time - first.metadata.time > duration || retainedCost > byteLimit
    {
      retainedCost -= first.retainedCost
      samples.removeFirst()
      evictedSamples += 1
    }
  }
}
