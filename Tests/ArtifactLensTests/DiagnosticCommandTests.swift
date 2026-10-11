import AppKit
import ArtifactCore
import Foundation
import Testing

@testable import ArtifactLens

private struct CommandOutput: Decodable {
  struct Sample: Decodable {
    let sampleID: UUID
    let capturedAt: String
    let time: Double
    let status: String
    let readingText: String?
    let parsedArtifact: Artifact?
    let savedArtifact: Artifact?
    let savedArtifactComparison: String
    let parserError: String?
  }
  let status: String
  let verifiedContextSupplied: Bool
  let annotation: DiagnosticAnnotation
  let annotationComparison: String
  let samples: [Sample]
}

private func commandFolder() throws -> URL {
  let folder = FileManager.default.temporaryDirectory.appending(path: "Replay-\(UUID())")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
  return folder
}

private func commandArtifact(em: Double = 19) throws -> Artifact {
  try Artifact(
    setName: "Synthetic Set", slot: .plume, main: .atk, level: 0,
    substats: [Substat(.hp, 209), Substat(.def, 16), Substat(.elementalMastery, em)],
    unactivated: Substat(.critDamage, 6.2))
}

private func commandContext(
  in folder: URL, pieceName: String = "Synthetic Feather", confirmed: Bool = true
) throws -> URL {
  struct Input: Encodable {
    let artifact: Artifact
    let pieceName: String
    let fiveStarsConfirmed: Bool
  }
  let file = folder.appending(path: "context.json")
  try JSONEncoder().encode(
    Input(artifact: commandArtifact(), pieceName: pieceName, fiveStarsConfirmed: confirmed)
  ).write(to: file)
  return file
}

private func commandReport(samples: [DiagnosticSample], session: UUID) -> DiagnosticReport {
  DiagnosticReport(
    id: UUID(),
    context: DiagnosticReportContext(
      appVersion: "test", build: "synthetic-build", osVersion: "test", pipelineVersion: "test",
      settings: ["private-setting": "DO NOT PRINT SETTINGS"], replayLimitations: []),
    annotation: DiagnosticAnnotation(
      issue: .wrongRead, notes: "Ada Lovelace: synthetic annotation", expectedReading: "+20",
      sampleID: samples.last?.metadata.id),
    snapshot: DiagnosticSnapshot(
      sessionID: session, frozenAt: 2, samples: samples, evictedSamples: 0, oversizedSamples: 0))
}

private func commandMetadata(session: UUID, mode: DiagnosticReadMode) -> DiagnosticSampleMetadata {
  DiagnosticSampleMetadata(
    id: UUID(), sessionID: session, capturedAt: Date(timeIntervalSince1970: 1001), time: 1,
    captureSize: CGSize(width: 1152, height: 768), assembledText: "SAVED TEXT IS NOT OCR",
    parserDecision: "Synthetic decision", confirmationDecision: "Synthetic confirmation",
    parsedArtifact: nil, states: [], mode: mode)
}

@Test func diagnosticCommandHelpAndInvalidArgumentsDoNotLaunchTheApp() throws {
  #expect(DiagnosticCommand.run(arguments: []) == nil)
  for arguments in [["--help"], ["-h"], ["replay", "--help"]] {
    let response = try #require(DiagnosticCommand.run(arguments: arguments))
    #expect(response.exitCode == 0)
    #expect(response.output.contains("Usage:"))
    #expect(response.error.isEmpty)
  }
  for arguments in [
    ["replay"], ["replay", ""], ["unknown"], ["--context", "x"],
    ["replay", "report", "--context"], ["replay", "report", "--other", "x"],
    ["replay", "report", "--context", ""], ["replay", "report", "--context", "--help"],
    ["replay", "report", "--context", "x", "extra"],
  ] {
    let response = try #require(DiagnosticCommand.run(arguments: arguments))
    #expect(response.exitCode == 64)
    #expect(response.output.isEmpty)
  }
}

@Test func diagnosticCommandRejectsMissingMalformedAndEmptyReportsWithoutWrites() async throws {
  let folder = try commandFolder()
  defer { try? FileManager.default.removeItem(at: folder) }
  let missing = folder.appending(path: "missing")
  #expect(DiagnosticCommand.run(arguments: ["replay", missing.path])?.exitCode == 66)
  #expect(DiagnosticCommand.run(arguments: ["replay", folder.path])?.exitCode == 65)
  let manifest = folder.appending(path: "manifest.json")
  let malformed = Data("{broken".utf8)
  try malformed.write(to: manifest)
  let response = try #require(DiagnosticCommand.run(arguments: ["replay", folder.path]))
  #expect(response.exitCode == 65)
  #expect(!response.error.contains(folder.path))
  #expect(try Data(contentsOf: manifest) == malformed)
  #expect(DiagnosticCommand.run(arguments: ["replay", manifest.path])?.exitCode == 65)
  let empty = try await DiagnosticExporter().save(
    commandReport(samples: [], session: UUID()), to: folder.appending(path: "empty"))
  #expect(DiagnosticCommand.run(arguments: ["replay", empty.path])?.exitCode == 65)
  #expect(!FileManager.default.fileExists(atPath: missing.path))
}

@Test func diagnosticCommandRequiresValidArtifactNameAndExplicitRarity() throws {
  let folder = try commandFolder()
  defer { try? FileManager.default.removeItem(at: folder) }
  let file = try commandContext(in: folder, confirmed: false)
  let args = ["replay", folder.path, "--context", file.path]
  #expect(DiagnosticCommand.run(arguments: args)?.exitCode == 64)
  _ = try commandContext(in: folder, pieceName: " 123 ")
  #expect(DiagnosticCommand.run(arguments: args)?.exitCode == 64)
  _ = try commandContext(in: folder)
  let text = try String(contentsOf: file, encoding: .utf8)
  try text.replacingOccurrences(of: "\"level\":0", with: "\"level\":21").write(
    to: file, atomically: false, encoding: .utf8)
  #expect(DiagnosticCommand.run(arguments: args)?.exitCode == 64)
  try Data("{}".utf8).write(to: file)
  #expect(DiagnosticCommand.run(arguments: args)?.exitCode == 64)
  #expect(
    DiagnosticCommand.run(arguments: ["replay", folder.path, "--context", folder.path])?.exitCode
      == 64)
}

@Test func diagnosticCommandDistinguishesMissingContextPartialInventoryAndReplayFailure()
  async throws
{
  let folder = try commandFolder()
  defer { try? FileManager.default.removeItem(at: folder) }
  let context = try commandContext(in: folder)
  let session = UUID()
  for (mode, expectedCode, expectedStatus) in [
    (DiagnosticReadMode.inventory, Int32(3), "partial-inventory"),
    (.enhance, Int32(1), "ocr-failure"), (.unknown, Int32(1), "ocr-failure"),
  ] {
    let report = try await DiagnosticExporter().save(
      commandReport(
        samples: [
          DiagnosticSample(metadata: commandMetadata(session: session, mode: mode), inputs: [])
        ],
        session: session), to: folder.appending(path: mode.rawValue))
    let missing = try #require(DiagnosticCommand.run(arguments: ["replay", report.path]))
    #expect(missing.exitCode == 2)
    let result = try #require(
      DiagnosticCommand.run(arguments: ["replay", report.path, "--context", context.path]))
    #expect(result.exitCode == expectedCode)
    let output = try JSONDecoder().decode(CommandOutput.self, from: Data(result.output.utf8))
    #expect(output.samples[0].status == expectedStatus)
    #expect(output.samples[0].parsedArtifact == nil)
    #expect(output.samples[0].readingText == nil)
    #expect(!result.output.contains("SAVED TEXT IS NOT OCR"))
    #expect(!result.output.contains("DO NOT PRINT SETTINGS"))
  }
}

@MainActor
private func commandEnhanceImage() throws -> CGImage {
  let context = try #require(
    CGContext(
      data: nil, width: 1152, height: 768, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
  )
  context.setFillColor(NSColor.darkGray.cgColor)
  context.fill(CGRect(x: 0, y: 0, width: 1152, height: 768))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  defer { NSGraphicsContext.restoreGraphicsState() }
  for (text, x, y) in [
    ("Plume of Death / Synthetic Feather", 85.0, 710.0), ("+0", 705, 640),
    ("ATK", 720, 580), ("47", 1090, 580), ("HP", 720, 535), ("209", 1090, 535),
    ("DEF", 720, 503), ("16", 1090, 503), ("Elemental Mastery", 720, 471),
    ("19", 1090, 471), ("CRIT DMG", 720, 438), ("(unactivated)", 720, 419),
    ("6.2%", 1080, 438),
  ] {
    (text as NSString).draw(
      at: NSPoint(x: x, y: y),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.white,
      ])
  }
  return try #require(context.makeImage())
}

@MainActor
@Test func diagnosticCommandSavedSyntheticReportRerunsVisionAndNeverUsesAnnotationsAsContext()
  async throws
{
  let folder = try commandFolder()
  defer { try? FileManager.default.removeItem(at: folder) }
  let context = try commandContext(in: folder)
  let expected = try commandArtifact()
  let session = UUID()
  var reader = try DiagnosticReader(sessionID: session)
  reader.setEnabled(true)
  let image = try commandEnhanceImage()
  _ = reader.read(image, at: 1, capturedAt: Date(timeIntervalSince1970: 1001))
  _ = try reader.read(image, at: 1.5, capturedAt: Date(timeIntervalSince1970: 1001.5)).result.get()
  _ = try reader.read(image, at: 2, capturedAt: Date(timeIntervalSince1970: 1002)).result.get()
  var samples = try reader.freeze(at: 2).samples
  samples[1].metadata.parsedArtifact = expected
  samples[2].metadata.parsedArtifact = try commandArtifact(em: 23)
  // Conflicting saved OCR proves replay consumes pixels, not recognized-text metadata.
  samples = samples.map { sample in
    let metadata = DiagnosticSampleMetadata(
      id: sample.metadata.id, sessionID: session, capturedAt: sample.metadata.capturedAt,
      time: sample.metadata.time, captureSize: sample.metadata.captureSize,
      assembledText: "SAVED TEXT IS NOT OCR", parserDecision: "Synthetic decision",
      confirmationDecision: "Synthetic confirmation",
      parsedArtifact: sample.metadata.parsedArtifact,
      states: [], mode: .enhance, resetsConfirmation: sample.metadata.resetsConfirmation)
    return DiagnosticSample(
      metadata: metadata,
      inputs: sample.inputs.map { input in
        DiagnosticInput(
          metadata: DiagnosticInputMetadata(
            kind: input.metadata.kind, cropBounds: input.metadata.cropBounds,
            configuration: input.metadata.configuration,
            observations: [
              DiagnosticText(
                text: "NOT REAL OCR", bounds: CGRect(x: 0, y: 0, width: 1, height: 1), confidence: 1
              )
            ],
            recognitionError: nil, isExactOCRInput: true), pixels: input.pixels)
      })
  }
  let report = try await DiagnosticExporter().save(
    commandReport(samples: samples, session: session), to: folder.appending(path: "report"))
  let files = try FileManager.default.contentsOfDirectory(
    at: report, includingPropertiesForKeys: nil)
  let before = try files.map { try Data(contentsOf: $0) }
  let result = try #require(
    DiagnosticCommand.run(arguments: ["replay", report.path, "--context", context.path]))
  let output = try JSONDecoder().decode(CommandOutput.self, from: Data(result.output.utf8))
  #expect(result.exitCode == 1)  // The first retained frame has no confirmation history.
  #expect(output.status == "replay-failure")
  #expect(output.verifiedContextSupplied)
  #expect(output.samples.map(\.sampleID) == samples.map(\.metadata.id))
  #expect(output.samples.map(\.time) == [1, 1.5, 2])
  #expect(output.samples[2].capturedAt == "1970-01-01T00:16:42Z")
  #expect(output.samples[0].status == "ocr-failure")
  #expect(output.samples[1].status == "parsed")
  #expect(output.samples[1].parsedArtifact?.signature == expected.signature)
  #expect(output.samples[1].savedArtifactComparison == "same-signature")
  #expect(output.samples[2].savedArtifactComparison == "different-signature")
  #expect(output.annotation.expectedReading == "+20")
  #expect(output.annotationComparison.contains("no automatic semantic equality"))
  #expect(!result.output.contains("SAVED TEXT IS NOT OCR"))
  #expect(!result.output.contains("NOT REAL OCR"))
  #expect(!result.output.contains(folder.path))
  let noContext = try #require(DiagnosticCommand.run(arguments: ["replay", report.path]))
  let missing = try JSONDecoder().decode(CommandOutput.self, from: Data(noContext.output.utf8))
  #expect(noContext.exitCode == 2)
  #expect(!missing.verifiedContextSupplied)
  #expect(missing.samples[1].status == "missing-context")
  #expect(missing.samples[1].readingText == output.samples[1].readingText)
  #expect(missing.samples[1].parsedArtifact == nil)
  _ = try commandContext(in: folder, pieceName: "Different Feather")
  let wrongContext = try #require(
    DiagnosticCommand.run(arguments: ["replay", report.path, "--context", context.path]))
  let wrong = try JSONDecoder().decode(CommandOutput.self, from: Data(wrongContext.output.utf8))
  #expect(wrongContext.exitCode == 1)
  #expect(wrong.samples[1].status == "parser-failure")
  #expect(wrong.samples[1].parserError?.contains("does not match") == true)
  #expect(try files.map { try Data(contentsOf: $0) } == before)
  #expect(
    try FileManager.default.contentsOfDirectory(at: report, includingPropertiesForKeys: nil).count
      == files.count)
}
