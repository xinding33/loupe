import Darwin
import Foundation
import LoupeCore

enum DiagnosticCommand {
  struct Response {
    let exitCode: Int32
    let output: String
    let error: String
  }

  private struct ContextInput: Decodable {
    let artifact: Artifact
    let pieceName: String
    let fiveStarsConfirmed: Bool
  }

  private struct SampleOutput: Encodable {
    let sampleID: UUID
    let capturedAt: Date
    let time: TimeInterval
    let mode: DiagnosticReadMode
    let status: String
    let readingText: String?
    let readingConfidence: Float?
    let readingError: String?
    let parsedArtifact: Artifact?
    let parserError: String?
    let savedArtifact: Artifact?
    let savedParserDecision: String
    let savedArtifactComparison: String
  }

  private struct Output: Encodable {
    let reportID: UUID
    let recordedAppVersion: String
    let recordedBuild: String
    let recordedPipelineVersion: String
    let replayBuild: String
    let verifiedContextSupplied: Bool
    let annotation: DiagnosticAnnotation
    let annotationComparison: String
    let limitations: [String]
    let status: String
    let samples: [SampleOutput]
  }

  static let help = """
    Usage: Loupe replay REPORT_DIRECTORY [--context CONTEXT.json]
           Loupe replay --help
           Loupe --diagnose

    --diagnose prints the version, signing, update and permission state, then exits.

    Replay reads only the selected local report and optional context file.
    It reruns Vision and the parser, without starting the app, capture, or inventory.
    Context JSON: {"artifact": <Artifact>, "pieceName": "...", "fiveStarsConfirmed": true}
    Supply independently verified Inventory context, never copied unverified saved OCR.
    Without context, OCR still runs but parser replay is unavailable.
    Inventory crops are partial evidence and cannot reproduce full-window Inventory OCR.
    JSON output compares artifact signatures; annotations remain free text for human review.
    No report files or inventory are written. Output can contain private artifact/annotation text.
    Exit: 0 complete; 1 OCR/parser failure; 2 missing context; 3 partial evidence;
          64 invalid arguments/context; 65 invalid or empty report; 66 report not found.
    With no arguments, Loupe starts the desktop app normally.
    See docs/diagnostic-replay.md for context format and replay limits.
    """

  // Dispatch before NSApplication, AppDelegate, and Model can create live services.
  static func dispatchIfRequested() {
    guard let response = run(arguments: Array(CommandLine.arguments.dropFirst())) else { return }
    if !response.output.isEmpty {
      FileHandle.standardOutput.write(Data((response.output + "\n").utf8))
    }
    if !response.error.isEmpty {
      FileHandle.standardError.write(Data((response.error + "\n").utf8))
    }
    exit(response.exitCode)
  }

  static func run(arguments: [String]) -> Response? {
    guard !arguments.isEmpty else { return nil }
    if arguments == ["--help"] || arguments == ["-h"] || arguments == ["replay", "--help"] {
      return Response(exitCode: 0, output: help, error: "")
    }
    guard arguments.first == "replay", arguments.count == 2 || arguments.count == 4,
      !arguments[1].isEmpty, !arguments[1].hasPrefix("-"),
      arguments.count == 2
        || (arguments[2] == "--context" && !arguments[3].isEmpty
          && !arguments[3].hasPrefix("-"))
    else { return failure(64, "Invalid replay arguments.\n\(help)") }

    let context: DiagnosticReplayContext?
    if arguments.count == 4 {
      do {
        let input = try JSONDecoder().decode(
          ContextInput.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[3])))
        let name = input.pieceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard input.fiveStarsConfirmed, !Artifact.normalizeSet(name).isEmpty else {
          return failure(64, "Context requires a piece name and fiveStarsConfirmed: true.")
        }
        context = DiagnosticReplayContext(artifact: input.artifact, pieceName: name)
      } catch {
        return failure(
          64,
          "Cannot read valid context JSON. Verify the artifact fields and five-star confirmation.")
      }
    } else {
      context = nil
    }

    let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
    guard FileManager.default.fileExists(atPath: folder.path) else {
      return failure(
        66, "Report directory does not exist. Supply an explicit saved report directory.")
    }
    let report: DiagnosticReport
    do {
      report = try DiagnosticReportReader.read(from: folder)
    } catch {
      return failure(
        65, "Cannot read report: invalid, unsupported, incomplete, or unreadable bundle.")
    }
    guard !report.snapshot.samples.isEmpty else {
      return failure(65, "Report contains no retained samples to replay.")
    }

    let results = DiagnosticReplay.run(report, context: context)
    let samples = zip(report.snapshot.samples, results).map { sample, result in
      let reading = try? result.reading.get()
      let artifact = try? result.parsed.get()
      let status: String
      if sample.metadata.mode == .inventory {
        status = "partial-inventory"
      } else if reading == nil {
        status = "ocr-failure"
      } else if context == nil {
        status = "missing-context"
      } else {
        status = artifact == nil ? "parser-failure" : "parsed"
      }
      let comparison: String
      if let artifact, let saved = sample.metadata.parsedArtifact {
        comparison =
          artifact.signature == saved.signature ? "same-signature" : "different-signature"
      } else {
        comparison = "unavailable"
      }
      return SampleOutput(
        sampleID: result.sampleID, capturedAt: sample.metadata.capturedAt, time: result.time,
        mode: sample.metadata.mode, status: status, readingText: reading?.text,
        readingConfidence: reading?.confidence, readingError: message(result.reading),
        parsedArtifact: artifact, parserError: message(result.parsed),
        savedArtifact: sample.metadata.parsedArtifact,
        savedParserDecision: sample.metadata.parserDecision, savedArtifactComparison: comparison)
    }
    let code: Int32
    let status: String
    if context == nil {
      (code, status) = (2, "missing-context")
    } else if samples.contains(where: {
      $0.status == "ocr-failure" || $0.status == "parser-failure"
    }) {
      (code, status) = (1, "replay-failure")
    } else if samples.contains(where: { $0.status == "partial-inventory" }) {
      (code, status) = (3, "partial-inventory")
    } else {
      (code, status) = (0, "complete")
    }
    let output = Output(
      reportID: report.id, recordedAppVersion: report.context.appVersion,
      recordedBuild: report.context.build, recordedPipelineVersion: report.context.pipelineVersion,
      replayBuild: Bundle.main.object(forInfoDictionaryKey: "LoupeBuildFingerprint")
        as? String
        ?? "unpackaged",
      verifiedContextSupplied: context != nil, annotation: report.annotation,
      annotationComparison: "Free-text annotation only; no automatic semantic equality check.",
      limitations: report.context.replayLimitations + [
        "Inventory full-window OCR is unavailable from retained partial crops.",
        "Only retained confirmation history is replayed; initial history can be missing.",
        "This command replays OCR/parser results, not recommendations or placement.",
      ], status: status, samples: samples)
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      encoder.dateEncodingStrategy = .iso8601
      return Response(
        exitCode: code, output: String(decoding: try encoder.encode(output), as: UTF8.self),
        error: "")
    } catch {
      return failure(1, "Could not encode replay results.")
    }
  }

  private static func failure(_ code: Int32, _ message: String) -> Response {
    Response(exitCode: code, output: "", error: message)
  }

  private static func message<T>(_ result: Result<T, Error>) -> String? {
    if case .failure(let error) = result { return error.localizedDescription }
    return nil
  }
}
