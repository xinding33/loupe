import AppKit
import Foundation
import ImageIO
import LoupeCore
import Testing

@testable import Loupe

private func integrationContext() -> DiagnosticReportContext {
  DiagnosticReportContext(
    appVersion: "test", build: "test", osVersion: "test", pipelineVersion: "prepared-enhance-v1",
    settings: [:], replayLimitations: ["Explicit Inventory context required"])
}

private func integrationSnapshot(session: UUID) -> DiagnosticSnapshot {
  DiagnosticSnapshot(
    sessionID: session, frozenAt: 2,
    samples: [
      DiagnosticSample(
        metadata: DiagnosticSampleMetadata(
          id: UUID(), sessionID: session, capturedAt: Date(timeIntervalSince1970: 1), time: 1,
          captureSize: CGSize(width: 1920, height: 1080), assembledText: "",
          parserDecision: "No card",
          confirmationDecision: "No heading", parsedArtifact: nil, states: []), inputs: [])
    ],
    evictedSamples: 0, oversizedSamples: 0)
}

@MainActor
private final class DiagnosticFreezeGate {
  private var continuation: CheckedContinuation<DiagnosticSnapshot, Never>?
  private var waiting: CheckedContinuation<Void, Never>?
  func freeze() async -> DiagnosticSnapshot {
    await withCheckedContinuation {
      continuation = $0
      waiting?.resume()
      waiting = nil
    }
  }
  func waitUntilEntered() async {
    if continuation == nil { await withCheckedContinuation { waiting = $0 } }
  }
  func finish(_ snapshot: DiagnosticSnapshot) {
    continuation?.resume(returning: snapshot)
    continuation = nil
  }
}

@MainActor
@Test func diagnosticIntegrationRejectsFreezeAfterSessionChange() async {
  var collection = false
  let flow = DiagnosticReportFlow { collection = $0 }
  let session = UUID()
  flow.beginSession(session)
  flow.setOptedIn(true)
  #expect(collection)
  let gate = DiagnosticFreezeGate()
  let task = flow.request(context: integrationContext()) { await gate.freeze() }
  await gate.waitUntilEntered()
  flow.beginSession(nil)
  gate.finish(integrationSnapshot(session: session))
  await task?.value
  #expect(!flow.isPresented)
  #expect(!collection)
  #expect(flow.coverage.count == 0)
  flow.updateCoverage(
    DiagnosticCoverage(count: 5, duration: 2, imageBytes: 16, issue: nil), session: session)
  #expect(flow.coverage.count == 0)
}

@MainActor
@Test func diagnosticIntegrationBufferOffIsActionableAndDoesNotFreezeOrEnableCapture() {
  var collection = false
  let flow = DiagnosticReportFlow { collection = $0 }
  var froze = false
  #expect(!flow.optedIn)
  flow.request(context: integrationContext()) {
    froze = true
    return integrationSnapshot(session: UUID())
  }
  #expect(!froze)
  #expect(!collection)
  guard case .unavailable(let reason) = flow.phase else {
    Issue.record("Expected actionable no-evidence explanation")
    return
  }
  #expect(reason.contains("reproduce"))
  #expect(reason.contains("40"))
}

@MainActor
@Test func diagnosticIntegrationOptOutBeforeFreezeStartsPreventsTheOperation() async {
  let flow = DiagnosticReportFlow { _ in }
  let session = UUID()
  flow.beginSession(session)
  flow.setOptedIn(true)
  var froze = false
  let task = flow.request(context: integrationContext()) {
    froze = true
    return integrationSnapshot(session: session)
  }
  flow.setOptedIn(false)
  await task?.value
  #expect(!froze)
  #expect(!flow.isPresented)
}

@MainActor
@Test func diagnosticIntegrationDisableReleasesPreviewAndAnnotationsNeverApplyToInventory()
  async throws
{
  let folder = FileManager.default.temporaryDirectory.appending(
    path: "DiagnosticFlow-\(UUID().uuidString)")
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer {
    model.setEnabled(false)
    try? FileManager.default.removeItem(at: folder)
  }
  let session = UUID()
  model.diagnostics.beginSession(session)
  model.diagnostics.setOptedIn(true)
  let snapshot = integrationSnapshot(session: session)
  await model.diagnostics.request(context: integrationContext()) { snapshot }?.value
  #expect(model.diagnostics.isPresented)
  let annotation = DiagnosticAnnotation(
    issue: .wrongRead, notes: "Grace Hopper: synthetic", expectedReading: "CRIT DMG 99%",
    sampleID: snapshot.samples[0].metadata.id)
  await #expect(throws: (any Error).self) {
    try await model.diagnostics.save(
      to: folder.appending(path: "missing/report"), annotation: annotation)
  }
  #expect(model.diagnostics.isPresented)
  #expect(!model.diagnostics.isSaving)
  #expect(model.diagnostics.saveStatus.contains("failed"))
  let saved = try await model.diagnostics.save(
    to: folder.appending(path: "report"), annotation: annotation)
  let report = try DiagnosticReportReader.read(from: saved)
  #expect(report.annotation.expectedReading == "CRIT DMG 99%")
  #expect(report.snapshot.samples[0].metadata.parsedArtifact == nil)
  #expect(model.inventory.artifacts.isEmpty)
  #expect(model.current == nil)
  #expect(model.rawText.isEmpty)
  await model.diagnostics.request(context: integrationContext()) { snapshot }?.value
  #expect(model.diagnostics.isPresented)
  model.setEnabled(false)
  #expect(!model.diagnostics.isPresented)
  #expect(try DiagnosticReportReader.read(from: saved).annotation.notes == annotation.notes)
}

@MainActor
private func diagnosticEnhanceImage() throws -> CGImage {
  let context = try #require(
    CGContext(
      data: nil, width: 1152, height: 768, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  )
  context.setFillColor(NSColor(calibratedRed: 0.28, green: 0.20, blue: 0.14, alpha: 1).cgColor)
  context.fill(CGRect(x: 0, y: 0, width: 1152, height: 768))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  defer { NSGraphicsContext.restoreGraphicsState() }
  func draw(_ text: String, _ x: Double, _ y: Double) {
    (text as NSString).draw(
      at: NSPoint(x: x, y: y),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.white,
      ])
  }
  draw("Plume of Death / Feather of Indelible Sin", 85, 710)
  draw("+0", 705, 640)
  draw("ATK", 720, 580)
  draw("47", 1090, 580)
  draw("HP", 720, 535)
  draw("209", 1090, 535)
  draw("DEF", 720, 503)
  draw("16", 1090, 503)
  draw("Elemental Mastery", 720, 471)
  draw("19", 1090, 471)
  draw("CRIT DMG", 720, 438)
  draw("(unactivated)", 720, 419)
  draw("6.2%", 1080, 438)
  return try #require(context.makeImage())
}

@MainActor
@Test func diagnosticIntegrationExactPreparedInputsReplayThroughVisionAndParser() throws {
  let image = try diagnosticEnhanceImage()
  var enabled = try DiagnosticReader(sessionID: UUID())
  var disabled = try DiagnosticReader(sessionID: UUID())
  enabled.setEnabled(true)
  _ = enabled.read(image, at: 1)
  _ = disabled.read(image, at: 1)
  let withEvidence = try enabled.read(image, at: 1.5).result.get()
  let withoutEvidence = try disabled.read(image, at: 1.5).result.get()
  #expect(withEvidence.text == withoutEvidence.text)
  #expect(withEvidence.isEnhancement && withoutEvidence.isEnhancement)
  #expect(disabled.buffer.samples.isEmpty)
  let report = DiagnosticReport(
    id: UUID(), context: integrationContext(),
    annotation: DiagnosticAnnotation(
      issue: .wrongRead, notes: "", expectedReading: "IGNORE THIS", sampleID: nil),
    snapshot: try enabled.freeze(at: 2))
  #expect(report.snapshot.samples.count == 2)
  #expect(
    report.snapshot.samples.allSatisfy {
      $0.inputs.count == 2 && $0.inputs.allSatisfy(\.metadata.isExactOCRInput)
    })
  let previous = try Artifact(
    setName: "Night of the Sky's Unveiling", slot: .plume, main: .atk, level: 0,
    substats: [Substat(.hp, 209), Substat(.def, 16), Substat(.elementalMastery, 19)],
    unactivated: Substat(.critDamage, 6.2))
  let replay = DiagnosticReplay.run(
    report,
    context: DiagnosticReplayContext(
      artifact: previous, pieceName: "Feather of Indelible Sin"))
  #expect(try replay[1].reading.get().text == withEvidence.text)
  #expect(try replay[1].parsed.get().signature == previous.signature)
  #expect(replay.map(\.time) == [1, 1.5])
  let missingContext = DiagnosticReplay.run(report, context: nil)
  #expect(throws: DiagnosticError.self) { try missingContext[1].parsed.get() }
}

@Test func diagnosticIntegrationUnknownScreenProducesOnlyMetadata() throws {
  let pixels = try DiagnosticPixels(
    width: 600, height: 400, bytes: Data(repeating: 0, count: 600 * 400 * 4))
  var reader = try DiagnosticReader(sessionID: UUID())
  reader.setEnabled(true)
  let result = reader.read(try pixels.makeImage(), at: 1)
  #expect(throws: (any Error).self) { try result.result.get() }
  let sample = try #require(reader.buffer.samples.first)
  #expect(sample.inputs.isEmpty)
  #expect(sample.metadata.mode == .inventory)
  #expect(!sample.metadata.confirmationDecision.isEmpty)
  #expect(reader.coverage.imageBytes == 0)
}

@MainActor
@Test func diagnosticIntegrationInventoryRetainsOnlyItsExistingSelectedCardCrop() throws {
  let context = try #require(
    CGContext(
      data: nil, width: 1152, height: 768, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  )
  context.setFillColor(NSColor.darkGray.cgColor)
  context.fill(CGRect(x: 0, y: 0, width: 1152, height: 768))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  let lines = [
    "Feather of Indelible Sin", "Plume of Death", "ATK", "47", "+0", "HP+209",
    "DEF+16", "Elemental Mastery+19", "CRIT DMG+6.2% (unactivated)", "Synthetic Set:",
  ]
  for (index, line) in lines.enumerated() {
    (line as NSString).draw(
      at: NSPoint(x: 650, y: 700 - index * 35),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.white,
      ])
  }
  NSGraphicsContext.restoreGraphicsState()
  let image = try #require(context.makeImage())
  var enabled = try DiagnosticReader(sessionID: UUID())
  enabled.setEnabled(true)
  var disabled = LiveCardOCR()
  let actual = try enabled.read(image, at: 1).result.get()
  let plain = try disabled.read(image, at: 1)
  #expect(actual.text == plain.text)
  #expect(!actual.isEnhancement)
  let sample = try #require(enabled.buffer.samples.first)
  #expect(sample.metadata.mode == .inventory)
  #expect(sample.inputs.count == 1)
  let input = try #require(sample.inputs.first)
  #expect(input.metadata.kind == .inventoryCard)
  #expect(!input.metadata.isExactOCRInput)
  #expect(input.pixels.width < image.width)
  #expect(input.pixels.height < image.height)
  var replay = LiveCardOCR()
  #expect(throws: DiagnosticError.self) { try replay.replay(sample) }
}

@Test func diagnosticIntegrationPreservesVisionBoundsAcrossAnImageEdge() throws {
  let session = UUID()
  let bounds = CGRect(x: -0.000062, y: 0.156, width: 0.429, height: 0.274)
  let input = DiagnosticInput(
    metadata: DiagnosticInputMetadata(
      kind: .enhanceStats, cropBounds: CGRect(x: 100, y: 100, width: 200, height: 200),
      configuration: DiagnosticOCRConfiguration(
        revision: 3, languages: ["en-US"], accurate: true, languageCorrection: false,
        minimumTextHeight: 0.01),
      observations: [DiagnosticText(text: "ATK", bounds: bounds, confidence: 1)],
      recognitionError: nil),
    pixels: try DiagnosticPixels(width: 1, height: 1, bytes: Data([255, 255, 255, 255])))
  var buffer = try DiagnosticBuffer(sessionID: session)
  buffer.setEnabled(true)
  #expect(
    try buffer.append(
      DiagnosticSample(
        metadata: integrationSnapshot(session: session).samples[0].metadata, inputs: [input]))
      == .retained)
  #expect(buffer.samples.first?.inputs.first?.metadata.observations.first?.bounds == bounds)
}

@Test func diagnosticIntegrationParserCompletionIsLinkedAndInvalidUpdatesAreAtomic() throws {
  let session = UUID()
  let sample = integrationSnapshot(session: session).samples[0]
  let key = DiagnosticSampleKey(sessionID: session, id: sample.metadata.id, time: 1)
  let artifact = try Artifact(
    setName: "Synthetic Set", slot: .plume, main: .atk, level: 0,
    substats: [Substat(.hp, 209), Substat(.def, 16), Substat(.elementalMastery, 19)])
  var buffer = try DiagnosticBuffer(sessionID: session)
  buffer.setEnabled(true)
  _ = try buffer.append(sample)
  try buffer.finishReading(
    key, artifact: artifact, decision: "Parsed",
    state: DiagnosticState(
      time: 1.5, displayedSampleID: sample.metadata.id, readingState: "verified",
      displayedText: "Verified plume", recommendation: nil, placement: nil))
  #expect(buffer.samples[0].metadata.parsedArtifact == artifact)
  #expect(buffer.samples[0].metadata.parserDecision == "Parsed")
  #expect(buffer.samples[0].metadata.states[0].displayedSampleID == key.id)
  let cost = buffer.retainedCost
  #expect(throws: DiagnosticError.self) {
    try buffer.finishReading(
      key, artifact: nil, decision: String(repeating: "x", count: 4096),
      state: DiagnosticState(
        time: 1, displayedSampleID: nil, readingState: "invalid", displayedText: "",
        recommendation: nil, placement: nil))
  }
  #expect(buffer.retainedCost == cost)
  #expect(buffer.samples[0].metadata.parsedArtifact == artifact)
  #expect(buffer.samples[0].metadata.parserDecision == "Parsed")
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["LOUPE_FIXTURES"] != nil))
func diagnosticRecordedEnhanceEnabledDisabledAndReplayAgree() throws {
  let path = try #require(ProcessInfo.processInfo.environment["LOUPE_FIXTURES"])
  let folder = URL(fileURLWithPath: path, isDirectory: true)
  let text = try String(contentsOf: folder.appending(path: "expected.txt"), encoding: .utf8)
  let previous = try CardParser.parse(text, fiveStarsConfirmed: true)
  let name = try #require(text.components(separatedBy: .newlines).first)
  let files = try FileManager.default.contentsOfDirectory(
    at: folder, includingPropertiesForKeys: nil
  )
  .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
  #expect(files.count >= 20)
  var disabled = LiveCardOCR()
  var enabled = try DiagnosticReader(sessionID: UUID())
  enabled.setEnabled(true)
  var replay = LiveCardOCR()
  var successes = [0, 0, 0]
  var stabilities = [CardStability(), CardStability(), CardStability()]
  var acquired = [false, false, false]
  var cleared = [0, 0, 0]
  for (index, file) in files.enumerated() {
    let source = try #require(CGImageSourceCreateWithURL(file as CFURL, nil))
    let frame = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let time = Double(index) * 0.5
    let plain = Result { try disabled.read(frame, at: time) }
    let recorded = enabled.read(frame, at: time)
    _ = try #require(recorded.key, "\(enabled.coverage.issue ?? "No retained sample key")")
    let sample = try #require(enabled.buffer.samples.last)
    #expect(sample.metadata.time == time)
    #expect(sample.inputs.count == 2)
    let replayed = Result { try replay.replay(sample) }
    var signatures: [String?] = []
    for (path, result) in [plain, recorded.result, replayed].enumerated() {
      let artifact = try? result.get().resolveEnhancement(previous: previous, pieceName: name)
      signatures.append(artifact?.signature)
      if let artifact {
        #expect(artifact.signature == previous.signature)
        successes[path] += 1
      }
      stabilities[path].observe(artifact?.signature, at: Date(timeIntervalSince1970: time))
      if acquired[path] && stabilities[path].signature == nil { cleared[path] += 1 }
      acquired[path] = acquired[path] || stabilities[path].isVerified
    }
    #expect(signatures[0] == signatures[1])
    #expect(signatures[1] == signatures[2])
  }
  for count in successes { #expect(Double(count) / Double(files.count) >= 0.95) }
  #expect(acquired == [true, true, true])
  #expect(cleared == [0, 0, 0])
  print(
    "Diagnostic fixture off/on/replay: \(successes) / \(files.count), post-acquisition clears: \(cleared)"
  )
}
