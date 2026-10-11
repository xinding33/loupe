import CryptoKit
import Foundation

struct DiagnosticReportContext: Codable, Sendable {
  let appVersion: String
  let build: String
  let osVersion: String
  let pipelineVersion: String
  let settings: [String: String]
  let replayLimitations: [String]
}

struct DiagnosticAnnotation: Codable, Sendable {
  enum Issue: String, Codable { case wrongRead, flicker, recommendation, placement }
  let issue: Issue
  let notes: String
  let expectedReading: String
  let sampleID: UUID?
}

struct DiagnosticReport: Sendable {
  let id: UUID
  let context: DiagnosticReportContext
  let annotation: DiagnosticAnnotation
  let snapshot: DiagnosticSnapshot

  // The UI must show every image and metadata before invoking save.
  static let previewWarning =
    "Review every crop and the report text. They may contain your UID, chat, or other identifying text. Reports stay local unless you share them."

  var replayFrames: [DiagnosticReplayFrame] {
    let start = snapshot.samples.first?.metadata.time ?? 0
    return snapshot.samples.map {
      DiagnosticReplayFrame(offset: $0.metadata.time - start, sample: $0)
    }
  }

  func previewMetadata() throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return String(decoding: try encoder.encode(DiagnosticManifest(self)), as: UTF8.self)
  }

  fileprivate func checked() throws -> Self {
    guard snapshot.frozenAt.isFinite, snapshot.evictedSamples >= 0,
      snapshot.oversizedSamples >= 0
    else { throw DiagnosticError.invalid("coverage") }
    var ids = Set<UUID>()
    var previous = -Double.infinity
    var cost = 0
    for sample in snapshot.samples {
      _ = try sample.checked()
      guard sample.metadata.sessionID == snapshot.sessionID,
        ids.insert(sample.metadata.id).inserted, sample.metadata.time >= previous,
        sample.metadata.time <= snapshot.frozenAt,
        snapshot.frozenAt - sample.metadata.time <= 10,
        sample.metadata.states.allSatisfy({ $0.time <= snapshot.frozenAt })
      else { throw DiagnosticError.invalid("sample linkage or coverage") }
      previous = sample.metadata.time
      cost += sample.retainedCost
      guard cost <= DiagnosticPixels.byteLimit else { throw DiagnosticError.oversized }
    }
    guard annotation.sampleID.map({ ids.contains($0) }) ?? true else {
      throw DiagnosticError.invalid("annotation sample is not retained")
    }
    return self
  }
}

struct DiagnosticReplayFrame: Sendable {
  let offset: TimeInterval
  let sample: DiagnosticSample
}

private struct DiagnosticManifest: Codable {
  struct Input: Codable {
    let metadata: DiagnosticInputMetadata
    let width: Int
    let height: Int
    let sha256: String
  }
  struct Sample: Codable {
    let metadata: DiagnosticSampleMetadata
    let inputs: [Input]
  }
  let schemaVersion: Int
  let pixelFormat: String
  let replayBoundary: String
  let id: UUID
  let context: DiagnosticReportContext
  let annotation: DiagnosticAnnotation
  let sessionID: UUID
  let frozenAt: TimeInterval
  let evictedSamples: Int
  let oversizedSamples: Int
  let retainedDuration: TimeInterval
  let imageBytes: Int
  let samples: [Sample]

  init(_ report: DiagnosticReport) {
    schemaVersion = 2
    pixelFormat = "sRGB-RGBA8-premultiplied-row-major"
    replayBoundary = "prepared-crop-inputs-v1"
    id = report.id
    context = report.context
    annotation = report.annotation
    sessionID = report.snapshot.sessionID
    frozenAt = report.snapshot.frozenAt
    evictedSamples = report.snapshot.evictedSamples
    oversizedSamples = report.snapshot.oversizedSamples
    retainedDuration = report.snapshot.retainedDuration
    imageBytes = report.snapshot.imageBytes
    samples = report.snapshot.samples.map { sample in
      Sample(
        metadata: sample.metadata,
        inputs: sample.inputs.map {
          Input(
            metadata: $0.metadata, width: $0.pixels.width, height: $0.pixels.height,
            sha256: diagnosticHash($0.pixels.bytes))
        })
    }
  }
}

private func diagnosticHash(_ data: Data) -> String {
  SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// Paths are derived from typed identities, never from a manifest-supplied path.
private func diagnosticImageURL(folder: URL, sampleID: UUID, index: Int) -> URL {
  folder.appending(path: "\(sampleID.uuidString)-\(index).rgba")
}

actor DiagnosticExporter {
  private var saving = false

  // Reject concurrent saves instead of retaining an unbounded queue of report snapshots.
  func save(_ report: DiagnosticReport, to destination: URL) async throws -> URL {
    guard !saving else { throw DiagnosticError.saveInProgress }
    saving = true
    defer { saving = false }
    return try await Task.detached(priority: .utility) {
      try Self.write(report, to: destination)
    }.value
  }

  private static func write(_ report: DiagnosticReport, to destination: URL) throws -> URL {
    _ = try report.checked()
    guard destination.isFileURL else { throw DiagnosticError.invalid("local destination required") }
    let manager = FileManager.default
    guard !manager.fileExists(atPath: destination.path) else {
      throw DiagnosticError.invalid("destination already exists; choose a new folder")
    }
    let staging = destination.deletingLastPathComponent().appending(
      path: ".diagnostic-\(UUID().uuidString).partial", directoryHint: .isDirectory)
    try manager.createDirectory(
      at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let manifest = try encoder.encode(DiagnosticManifest(report))
      guard manifest.count <= DiagnosticPixels.byteLimit else { throw DiagnosticError.oversized }
      for sample in report.snapshot.samples {
        for (index, input) in sample.inputs.enumerated() {
          try writePrivate(
            input.pixels.bytes,
            to: diagnosticImageURL(folder: staging, sampleID: sample.metadata.id, index: index))
        }
      }
      try writePrivate(manifest, to: staging.appending(path: "manifest.json"))
      try manager.moveItem(at: staging, to: destination)
      return destination
    } catch {
      do {
        try manager.removeItem(at: staging)
      } catch let cleanupError {
        throw DiagnosticError.invalid(
          "save failed: \(error.localizedDescription); partial report remains at \(staging.path): \(cleanupError.localizedDescription)"
        )
      }
      throw error
    }
  }

  private static func writePrivate(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .withoutOverwriting)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
  }
}

enum DiagnosticReportReader {
  // Call off the live OCR executor. This reads only the explicitly selected bundle.
  static func read(from folder: URL) throws -> DiagnosticReport {
    guard folder.isFileURL else { throw DiagnosticError.invalid("local report required") }
    let data = try readFile(
      folder.appending(path: "manifest.json"), maximum: DiagnosticPixels.byteLimit)
    let manifest = try JSONDecoder().decode(DiagnosticManifest.self, from: data)
    guard manifest.schemaVersion == 2,
      manifest.pixelFormat == "sRGB-RGBA8-premultiplied-row-major",
      manifest.replayBoundary == "prepared-crop-inputs-v1"
    else { throw DiagnosticError.invalid("unsupported report version or replay boundary") }
    var imageBytes = 0
    var samples: [DiagnosticSample] = []
    for sample in manifest.samples {
      var inputs: [DiagnosticInput] = []
      for (index, input) in sample.inputs.enumerated() {
        let count = try DiagnosticPixels.byteCount(width: input.width, height: input.height)
        guard count <= DiagnosticPixels.byteLimit - imageBytes else {
          throw DiagnosticError.oversized
        }
        imageBytes += count
        let bytes = try readFile(
          diagnosticImageURL(folder: folder, sampleID: sample.metadata.id, index: index),
          maximum: count)
        guard bytes.count == count, diagnosticHash(bytes) == input.sha256 else {
          throw DiagnosticError.invalid("missing, truncated, or changed crop pixels")
        }
        inputs.append(
          DiagnosticInput(
            metadata: input.metadata,
            pixels: try DiagnosticPixels(width: input.width, height: input.height, bytes: bytes)))
      }
      samples.append(DiagnosticSample(metadata: sample.metadata, inputs: inputs))
    }
    let snapshot = DiagnosticSnapshot(
      sessionID: manifest.sessionID, frozenAt: manifest.frozenAt, samples: samples,
      evictedSamples: manifest.evictedSamples, oversizedSamples: manifest.oversizedSamples)
    guard snapshot.imageBytes == manifest.imageBytes,
      snapshot.retainedDuration == manifest.retainedDuration
    else { throw DiagnosticError.invalid("coverage does not match samples") }
    return try DiagnosticReport(
      id: manifest.id, context: manifest.context, annotation: manifest.annotation,
      snapshot: snapshot
    ).checked()
  }

  private static func readFile(_ url: URL, maximum: Int) throws -> Data {
    let values = try url.resourceValues(forKeys: [
      .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey,
    ])
    guard values.isRegularFile == true, values.isSymbolicLink != true,
      let size = values.fileSize, size <= maximum
    else { throw DiagnosticError.invalid("report member is not a bounded regular file") }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maximum + 1) ?? Data()
    guard data.count <= maximum else { throw DiagnosticError.oversized }
    return data
  }
}
