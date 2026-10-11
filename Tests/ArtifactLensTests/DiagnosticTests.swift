import AppKit
import ArtifactCore
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import ArtifactLens

private let diagnosticSession = UUID()

private func diagnosticSample(
  at time: TimeInterval, session: UUID = diagnosticSession, text: String = "+0",
  artifact: Artifact? = nil
) throws -> DiagnosticSample {
  let pixels = try DiagnosticPixels(
    width: 2, height: 2,
    bytes: Data([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255]))
  return DiagnosticSample(
    metadata: DiagnosticSampleMetadata(
      id: UUID(), sessionID: session, capturedAt: Date(timeIntervalSince1970: 1000 + time),
      time: time, captureSize: CGSize(width: 1920, height: 1080), assembledText: text,
      parserDecision: "Waiting for stat rows", confirmationDecision: "One observation",
      parsedArtifact: artifact,
      states: []),
    inputs: [
      DiagnosticInput(
        metadata: DiagnosticInputMetadata(
          kind: .enhanceStats, cropBounds: CGRect(x: 1056, y: 86, width: 864, height: 475),
          configuration: DiagnosticOCRConfiguration(
            revision: 3, languages: ["en-US"], accurate: true, languageCorrection: false,
            minimumTextHeight: 0.01),
          observations: [
            DiagnosticText(
              text: text, bounds: CGRect(x: 0.2, y: 0.8, width: 0.1, height: 0.03), confidence: 0.91
            )
          ], recognitionError: nil), pixels: pixels)
    ])
}

private func diagnosticReport() throws -> DiagnosticReport {
  var buffer = try DiagnosticBuffer(sessionID: diagnosticSession)
  buffer.setEnabled(true)
  let parsed = try Artifact(
    setName: "Synthetic Set", slot: .plume, main: .atk, level: 0,
    substats: [Substat(.hp, 209), Substat(.def, 16), Substat(.elementalMastery, 19)])
  let first = try diagnosticSample(at: 12, artifact: parsed)
  let second = try diagnosticSample(at: 12.5, text: "+4")
  _ = try buffer.append(first)
  _ = try buffer.append(second)
  let benchmark = try Artifact(
    setName: "Synthetic Set", slot: .plume, main: .atk, level: 20,
    substats: [
      Substat(.hp, 209), Substat(.def, 16), Substat(.elementalMastery, 19),
      Substat(.critDamage, 38.8),
    ])
  try buffer.recordState(
    DiagnosticState(
      time: 12.75, displayedSampleID: first.metadata.id, readingState: "rechecking",
      displayedText: "Last verified card",
      recommendation: DiagnosticRecommendation(
        scoringVersion: "test-score-v1", dataVersion: "test-roles-v1", profile: "Crit",
        scope: "offPiece", weights: ["critDMG_": 1], comparisonPieces: [benchmark], excludedID: nil,
        metrics: ["chanceToBeatBest": 0.125], explanation: "Synthetic baseline"),
      placement: DiagnosticPlacement(
        window: CGRect(x: 200, y: 100, width: 1200, height: 800),
        displays: [CGRect(x: 0, y: 0, width: 1920, height: 1080)], selectedDisplay: 0,
        overlay: CGRect(x: 1500, y: 900, width: 280, height: 100), scale: 2)),
    sampleID: second.metadata.id, sessionID: diagnosticSession)
  return DiagnosticReport(
    id: UUID(),
    context: DiagnosticReportContext(
      appVersion: "test", build: "synthetic", osVersion: "test-os",
      pipelineVersion: "test-pipeline-v1",
      settings: ["sampleRate": "2"], replayLimitations: ["No pre-window confirmation history"]),
    annotation: DiagnosticAnnotation(
      issue: .flicker, notes: "Ada Lovelace: synthetic test", expectedReading: "+4",
      sampleID: second.metadata.id), snapshot: try buffer.freeze(at: 13))
}

private func diagnosticTemporaryDirectory() throws -> URL {
  let folder = FileManager.default.temporaryDirectory.appending(
    path: "ArtifactLens-DiagnosticTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
  return folder
}

@Test func diagnosticBufferEvictsByTimeAndReportsActualCoverage() throws {
  var buffer = try DiagnosticBuffer(sessionID: diagnosticSession)
  buffer.setEnabled(true)
  #expect(try buffer.append(diagnosticSample(at: 1)) == .retained)
  #expect(try buffer.append(diagnosticSample(at: 6)) == .retained)
  #expect(try buffer.append(diagnosticSample(at: 11)) == .retained)
  #expect(buffer.samples.count == 3)
  let snapshot = try buffer.freeze(at: 11.1)
  #expect(snapshot.samples.map(\.metadata.time) == [6, 11])
  #expect(snapshot.retainedDuration == 5)
  #expect(snapshot.evictedSamples == 1)
  #expect(snapshot.imageBytes == 32)
  #expect(buffer.samples.isEmpty)
  #expect(!buffer.isEnabled)
}

@Test func diagnosticBufferEvictsOldestUnderBytePressure() throws {
  let first = try diagnosticSample(at: 1)
  var buffer = try DiagnosticBuffer(sessionID: diagnosticSession, byteLimit: first.retainedCost * 2)
  buffer.setEnabled(true)
  _ = try buffer.append(first)
  _ = try buffer.append(diagnosticSample(at: 2))
  _ = try buffer.append(diagnosticSample(at: 3))
  #expect(buffer.samples.map(\.metadata.time) == [2, 3])
  #expect(buffer.retainedCost <= buffer.byteLimit)
  let snapshot = try buffer.freeze(at: 3)
  #expect(snapshot.evictedSamples == 1)
  #expect(snapshot.retainedDuration == 1)
}

@Test func diagnosticBufferRejectsOversizedInputWithoutLosingRecentEvidence() throws {
  let first = try diagnosticSample(at: 1)
  var buffer = try DiagnosticBuffer(sessionID: diagnosticSession, byteLimit: first.retainedCost)
  buffer.setEnabled(true)
  _ = try buffer.append(first)
  #expect(
    try buffer.append(diagnosticSample(at: 2, text: String(repeating: "x", count: 5000)))
      == .oversized)
  let snapshot = try buffer.freeze(at: 2)
  #expect(snapshot.samples.map(\.metadata.id) == [first.metadata.id])
  #expect(snapshot.oversizedSamples == 1)
  #expect(throws: DiagnosticError.self) {
    try DiagnosticPixels(width: Int.max, height: Int.max, bytes: Data())
  }
}

@Test func diagnosticBufferBoundsMetadataWithoutImagesOrAdvancingTime() throws {
  let source = try diagnosticSample(at: 1)
  let first = DiagnosticSample(metadata: source.metadata, inputs: [])
  var buffer = try DiagnosticBuffer(sessionID: diagnosticSession, byteLimit: first.retainedCost * 2)
  buffer.setEnabled(true)
  for _ in 0..<20 {
    let sample = try diagnosticSample(at: 1)
    _ = try buffer.append(DiagnosticSample(metadata: sample.metadata, inputs: []))
  }
  #expect(buffer.samples.count == 2)
  #expect(buffer.retainedCost <= buffer.byteLimit)
  #expect(try buffer.freeze(at: 1).evictedSamples == 18)
}

@Test func diagnosticDisableClearAndSessionChangeRejectLateSamples() throws {
  var buffer = try DiagnosticBuffer(sessionID: diagnosticSession)
  let first = try diagnosticSample(at: 1)
  #expect(try buffer.append(first) == .disabled)
  buffer.setEnabled(true)
  _ = try buffer.append(first)
  buffer.setEnabled(false)
  #expect(buffer.samples.isEmpty)
  #expect(buffer.retainedCost == 0)
  #expect(try buffer.append(first) == .disabled)
  buffer.setEnabled(true)
  _ = try buffer.append(first)
  buffer.clear()
  #expect(buffer.samples.isEmpty)
  _ = try buffer.append(first)
  let nextSession = UUID()
  buffer.beginSession(nextSession)
  #expect(buffer.samples.isEmpty)
  #expect(try buffer.append(first) == .wrongSession)
  #expect(try buffer.append(diagnosticSample(at: 0, session: nextSession)) == .retained)
}

@Test func diagnosticClockAndDuplicateIdentityCannotCorruptSequence() throws {
  var buffer = try DiagnosticBuffer(sessionID: diagnosticSession)
  buffer.setEnabled(true)
  let first = try diagnosticSample(at: 7)
  _ = try buffer.append(first)
  #expect(try buffer.append(diagnosticSample(at: 6)) == .outOfOrder)
  #expect(throws: DiagnosticError.self) { try buffer.append(first) }
  #expect(throws: DiagnosticError.self) { try buffer.expire(at: .nan) }
  #expect(throws: DiagnosticError.self) { try buffer.freeze(at: 6) }
  try buffer.expire(at: 18)
  #expect(buffer.samples.isEmpty)
}

@Test func diagnosticLateDisplayStateKeepsTriggerAndDisplayedIdentityDistinct() throws {
  let report = try diagnosticReport()
  let samples = report.snapshot.samples
  let state = try #require(samples[1].metadata.states.first)
  #expect(state.displayedSampleID == samples[0].metadata.id)
  #expect(state.time == 12.75)
  #expect(state.recommendation?.comparisonPieces.first?.level == 20)
  #expect(state.recommendation?.metrics["chanceToBeatBest"] == 0.125)
  #expect(state.placement?.selectedDisplay == 0)
  #expect(report.annotation.sampleID == samples[1].metadata.id)
}

@Test func diagnosticStateUpdatesRespectBudgetAndSession() throws {
  let first = try diagnosticSample(at: 1)
  var buffer = try DiagnosticBuffer(sessionID: diagnosticSession, byteLimit: first.retainedCost)
  buffer.setEnabled(true)
  _ = try buffer.append(first)
  let state = DiagnosticState(
    time: 2, displayedSampleID: first.metadata.id, readingState: "waiting",
    displayedText: "Checking",
    recommendation: nil, placement: nil)
  #expect(try !buffer.recordState(state, sampleID: first.metadata.id, sessionID: UUID()))
  #expect(try !buffer.recordState(state, sampleID: first.metadata.id, sessionID: diagnosticSession))
  #expect(buffer.samples.isEmpty)
  #expect(buffer.retainedCost == 0)
}

@Test func diagnosticCropsOwnOnlyTheirPixelsAndPreserveTheirOrientation() throws {
  let original = try DiagnosticPixels(
    width: 1024, height: 512, bytes: Data(repeating: 255, count: 1024 * 512 * 4))
  let crop = try #require(
    original.makeImage().cropping(to: CGRect(x: 20, y: 30, width: 16, height: 8)))
  let owned = try DiagnosticPixels(copying: crop)
  #expect(owned.bytes.count == 512)
  #expect(try owned.makeImage().bytesPerRow == 64)
  #expect(try owned.makeImage().dataProvider?.data.map { CFDataGetLength($0) } == 512)
  let colors = try diagnosticSample(at: 1).inputs[0].pixels
  let copied = try DiagnosticPixels(copying: colors.makeImage())
  #expect(copied.bytes == colors.bytes)
}

@Test func diagnosticReportRoundTripsExactInputsTimingAndAnnotations() async throws {
  let folder = try diagnosticTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: folder) }
  let report = try diagnosticReport()
  let destination = folder.appending(path: "report")
  let saved = try await DiagnosticExporter().save(report, to: destination)
  let actual = try DiagnosticReportReader.read(from: saved)
  #expect(actual.id == report.id)
  #expect(actual.snapshot.retainedDuration == 0.5)
  #expect(actual.replayFrames.map(\.offset) == [0, 0.5])
  #expect(actual.snapshot.samples[0].metadata.capturedAt == Date(timeIntervalSince1970: 1012))
  #expect(
    actual.snapshot.samples[0].metadata.parsedArtifact?.signature
      == report.snapshot.samples[0].metadata.parsedArtifact?.signature)
  #expect(actual.snapshot.samples[1].metadata.parsedArtifact == nil)
  #expect(
    actual.snapshot.samples[1].inputs[0].pixels.bytes
      == report.snapshot.samples[1].inputs[0].pixels.bytes)
  #expect(actual.snapshot.samples[1].inputs[0].metadata.observations[0].text == "+4")
  #expect(actual.snapshot.samples[1].inputs[0].metadata.observations[0].confidence == 0.91)
  #expect(actual.snapshot.samples[1].inputs[0].metadata.configuration.revision == 3)
  #expect(
    actual.snapshot.samples[1].metadata.states[0].displayedSampleID
      == actual.snapshot.samples[0].metadata.id)
  #expect(actual.annotation.expectedReading == "+4")
  #expect(actual.annotation.notes == "Ada Lovelace: synthetic test")
  #expect(actual.context.settings["sampleRate"] == "2")
  #expect(actual.snapshot.samples[1].metadata.parserDecision == "Waiting for stat rows")
}

@Test(arguments: ["version", "duplicate", "coverage", "dimensions", "confidence", "invalidJSON"])
func diagnosticReaderRejectsMalformedManifests(_ corruption: String) async throws {
  let folder = try diagnosticTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: folder) }
  let report = try diagnosticReport()
  let saved = try await DiagnosticExporter().save(report, to: folder.appending(path: "report"))
  let manifestURL = saved.appending(path: "manifest.json")
  var json = try #require(
    JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
  switch corruption {
  case "version": json["schemaVersion"] = 999
  case "coverage": json["retainedDuration"] = 9
  case "duplicate":
    let samples = try #require(json["samples"] as? [[String: Any]])
    json["samples"] = [samples[0], samples[0]]
  case "dimensions", "confidence":
    var samples = try #require(json["samples"] as? [[String: Any]])
    var inputs = try #require(samples[0]["inputs"] as? [[String: Any]])
    if corruption == "dimensions" {
      inputs[0]["width"] = Int.max
    } else {
      var metadata = try #require(inputs[0]["metadata"] as? [String: Any])
      var observations = try #require(metadata["observations"] as? [[String: Any]])
      observations[0]["confidence"] = 2
      metadata["observations"] = observations
      inputs[0]["metadata"] = metadata
    }
    samples[0]["inputs"] = inputs
    json["samples"] = samples
  default: break
  }
  let bytes =
    corruption == "invalidJSON" ? Data("{".utf8) : try JSONSerialization.data(withJSONObject: json)
  try bytes.write(to: manifestURL)
  #expect(throws: (any Error).self) { try DiagnosticReportReader.read(from: saved) }
}

@Test(arguments: ["changed", "truncated", "missing", "symlink"])
func diagnosticReaderRejectsDamagedOrRedirectedPixels(_ corruption: String) async throws {
  let folder = try diagnosticTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: folder) }
  let report = try diagnosticReport()
  let saved = try await DiagnosticExporter().save(report, to: folder.appending(path: "report"))
  let pixels = saved.appending(path: "\(report.snapshot.samples[0].metadata.id.uuidString)-0.rgba")
  switch corruption {
  case "changed": try Data(repeating: 0, count: 16).write(to: pixels)
  case "truncated": try Data([1]).write(to: pixels)
  case "missing": try FileManager.default.removeItem(at: pixels)
  default:
    let moved = folder.appending(path: "elsewhere.rgba")
    try FileManager.default.moveItem(at: pixels, to: moved)
    try FileManager.default.createSymbolicLink(at: pixels, withDestinationURL: moved)
  }
  #expect(throws: (any Error).self) { try DiagnosticReportReader.read(from: saved) }
}

@Test func diagnosticSaveFailurePreservesExistingReportsAndCleansOnlyItsPartialFolder() async throws
{
  let folder = try diagnosticTemporaryDirectory()
  defer { try? FileManager.default.removeItem(at: folder) }
  let exporter = DiagnosticExporter()
  let report = try diagnosticReport()
  let missingParent = folder.appending(path: "missing/report")
  await #expect(throws: (any Error).self) { try await exporter.save(report, to: missingParent) }
  let tooLong = folder.appending(path: String(repeating: "x", count: 300))
  await #expect(throws: (any Error).self) { try await exporter.save(report, to: tooLong) }
  #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
  let saved = try await exporter.save(report, to: folder.appending(path: "kept"))
  let before = try Data(contentsOf: saved.appending(path: "manifest.json"))
  await #expect(throws: (any Error).self) { try await exporter.save(report, to: saved) }
  #expect(try Data(contentsOf: saved.appending(path: "manifest.json")) == before)
  var buffer = try DiagnosticBuffer(sessionID: diagnosticSession)
  buffer.setEnabled(false)
  #expect(try DiagnosticReportReader.read(from: saved).id == report.id)
}

/// Synthetic report-preview render. Writes a PNG only when ARTIFACT_LENS_UI_PROOF is set.
@MainActor
@Test func renderSyntheticReportPreviewWhenRequested() async throws {
  guard let output = ProcessInfo.processInfo.environment["ARTIFACT_LENS_UI_PROOF"] else { return }
  let flow = DiagnosticReportFlow { _ in }
  let host = NSHostingView(
    rootView: DiagnosticReportView(flow: flow, report: try diagnosticReport())
      .background(Color(nsColor: .windowBackgroundColor)).preferredColorScheme(.dark))
  let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 760, height: 760), styleMask: [.borderless],
    backing: .buffered, defer: false)
  window.appearance = NSAppearance(named: .darkAqua)
  window.contentView = host
  host.frame = window.contentLayoutRect
  try await Task.sleep(for: .milliseconds(500))
  host.layoutSubtreeIfNeeded()
  let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
  host.cacheDisplay(in: host.bounds, to: bitmap)
  try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
  try #require(bitmap.representation(using: .png, properties: [:])).write(
    to: URL(fileURLWithPath: output).appending(path: "report-preview.png"),
    options: .withoutOverwriting)
}
