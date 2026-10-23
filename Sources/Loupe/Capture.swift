import AppKit
import CoreImage
import LoupeCore
@preconcurrency import ScreenCaptureKit
import Vision

struct CardReading: Sendable {
  let text: String
  let fiveStars: Bool
  let confidence: Float
  var isEnhancement = false

  func resolveEnhancement(previous: Artifact, pieceName: String) throws -> Artifact {
    let artifact = try CardParser.parseEnhancement(text, previous: previous, pieceName: pieceName)
    // An exact match supplies context for noisy glyphs; changed stats still require confident OCR.
    guard confidence >= 0.65 || (confidence >= 0.5 && artifact.signature == previous.signature)
    else {
      throw ArtifactError("Waiting for a clearer reading of the changed artifact.")
    }
    return artifact
  }
}

enum CardOCR {
  static func read(_ image: CGImage) throws -> CardReading {
    if let snapshot = try enhancementSnapshot(image), let heading = snapshot.heading {
      let result = try EnhancementLayout.assemble(snapshot.regions, heading: heading)
      return CardReading(
        text: result.text, fiveStars: false, confidence: result.confidence, isEnhancement: true)
    }
    return try readInventory(image)
  }

  static func enhancementSnapshot(_ image: CGImage, diagnostics: DiagnosticOCRTrace? = nil) throws
    -> (
      heading: TextRegion?, regions: [TextRegion]
    )?
  {
    let header = try recognize(
      image, in: CGRect(x: 0.06, y: 0.03, width: 0.70, height: 0.09), targetWidth: 1400,
      correctWords: true, kind: .enhanceHeading, diagnostics: diagnostics)
    let regions = try recognize(
      image, in: CGRect(x: 0.55, y: 0.08, width: 0.45, height: 0.44), targetWidth: 1200,
      kind: .enhanceStats, diagnostics: diagnostics)
    return enhancementSnapshot(header: header, regions: regions)
  }

  static func enhancementSnapshot(header: [TextRegion], regions: [TextRegion]) -> (
    heading: TextRegion?, regions: [TextRegion]
  )? {
    let heading = header.first(where: { $0.text.contains("/") && $0.text.contains(" of ") })
    let normalized = EnhancementLayout.normalized(regions)
    if heading != nil
      || (normalized.filter { $0.bounds.minX > 0.8 }.count >= 3
        && normalized.filter { $0.bounds.minX < 0.8 && !$0.text.hasPrefix("+") }.count >= 3)
    {
      return (heading, normalized)
    }
    return nil
  }

  static func readInventory(_ image: CGImage, diagnostics: DiagnosticOCRTrace? = nil) throws
    -> CardReading
  {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.01
    try VNImageRequestHandler(cgImage: image).perform([request])
    let observations = request.results ?? []
    let slots = [
      "flower of life", "plume of death", "sands of eon", "goblet of eonothem", "circlet of logos",
    ]
    let anchors = observations.filter { obs in
      guard let text = obs.topCandidates(1).first?.string.lowercased() else { return false }
      return slots.contains { text.contains($0) }
    }
    guard anchors.count == 1, let anchor = anchors.first else {
      throw ArtifactError(
        "Open one artifact card in Inventory. Comparison screens are not supported yet.")
    }
    if anchor.topCandidates(1).first?.string.contains("/") == true {
      throw ArtifactError("Waiting for a readable Enhance title and stat table.")
    }
    let left = max(0, anchor.boundingBox.minX - 0.025)
    let right = min(1, left + 0.36)
    let card = observations.filter {
      $0.boundingBox.minX >= left && $0.boundingBox.midX < right
        && $0.boundingBox.minY <= anchor.boundingBox.maxY + 0.08
    }.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    if let diagnostics { recordInventoryCrop(image, card: card, trace: diagnostics) }
    let candidates = card.compactMap { $0.topCandidates(1).first }
    guard
      let level = card.first(where: {
        $0.topCandidates(1).first?.string.range(of: #"^\+\s*\d{1,2}$"#, options: .regularExpression)
          != nil
      }),
      let mainValue = card.last(where: {
        $0.boundingBox.minY > level.boundingBox.maxY
          && $0.topCandidates(1).first?.string.range(
            of: #"^\d[\d,.]*%?$"#, options: .regularExpression) != nil
      })
    else { throw ArtifactError("Waiting for a clear level and main-stat value.") }
    let band = CGRect(
      x: left, y: level.boundingBox.maxY, width: right - left,
      height: max(0, mainValue.boundingBox.minY - level.boundingBox.maxY))
    let fiveStars = countStars(in: image, band: band) == 5
    let relevant = zip(card, candidates).filter {
      $0.0.boundingBox.minY >= level.boundingBox.minY - 0.23
    }
    return CardReading(
      text: candidates.map(\.string).joined(separator: "\n"), fiveStars: fiveStars,
      confidence: relevant.map { $0.1.confidence }.min() ?? 0)
  }

  private static func recognize(
    _ image: CGImage, in area: CGRect, targetWidth: Double, correctWords: Bool = false,
    kind: DiagnosticInputMetadata.Kind, diagnostics: DiagnosticOCRTrace?
  ) throws
    -> [TextRegion]
  {
    let rect = CGRect(
      x: Double(image.width) * area.minX, y: Double(image.height) * area.minY,
      width: Double(image.width) * area.width, height: Double(image.height) * area.height
    ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let crop = image.cropping(to: rect)
    else { throw ArtifactError("Waiting for the Enhance stat table.") }
    let scale = targetWidth / Double(crop.width)
    guard
      let canvas = CGContext(
        data: nil, width: Int(Double(crop.width) * scale), height: Int(Double(crop.height) * scale),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { throw ArtifactError("Cannot prepare the Enhance stat table for OCR.") }
    canvas.interpolationQuality = .high
    canvas.draw(crop, in: CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
    guard let tableImage = canvas.makeImage() else {
      throw ArtifactError("Cannot prepare the Enhance stat table for OCR.")
    }
    return try PreparedCardOCR.read(
      tableImage, crop: rect, captureSize: CGSize(width: image.width, height: image.height),
      kind: kind, correctWords: correctWords, trace: diagnostics)
  }

  private static func countStars(in image: CGImage, band: CGRect) -> Int {
    let rect = CGRect(
      x: band.minX * Double(image.width), y: (1 - band.maxY) * Double(image.height),
      width: band.width * Double(image.width), height: band.height * Double(image.height)
    ).integral
    guard rect.height > 0, let crop = image.cropping(to: rect) else { return 0 }
    let width = crop.width
    let height = crop.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard
      let context = CGContext(
        data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return 0 }
    context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
    var runs: [Int] = []
    var run = 0
    for x in 0..<width {
      let gold = (0..<height).contains { y in
        let i = (y * width + x) * 4
        let r = Int(bytes[i])
        let g = Int(bytes[i + 1])
        let b = Int(bytes[i + 2])
        return r > 190 && g > 140 && b < 150 && g > b + 45
      }
      if gold {
        run += 1
      } else if run > 0 {
        runs.append(run)
        run = 0
      }
    }
    if run > 0 { runs.append(run) }
    return runs.filter { $0 >= max(3, image.width / 180) && $0 <= image.width / 25 }.count
  }
}

private final class FrameReader: NSObject, SCStreamOutput, @unchecked Sendable {
  let receive:
    @Sendable (Result<CardReading, Error>, DiagnosticSampleKey?, DiagnosticCoverage) -> Void
  let sessionID: UUID
  let gate = FrameGate()
  private let context = CIContext()
  private var latest: CGImage?
  var ocr: DiagnosticReader
  var recording: FrameRecording?
  init(
    sessionID: UUID, diagnosticsEnabled: Bool,
    receive:
      @escaping @Sendable (Result<CardReading, Error>, DiagnosticSampleKey?, DiagnosticCoverage) ->
      Void
  ) throws {
    self.sessionID = sessionID
    self.receive = receive
    ocr = try DiagnosticReader(sessionID: sessionID)
    ocr.setEnabled(diagnosticsEnabled)
  }
  func clear() {
    latest = nil
    recording = nil
    ocr.clear()
    context.clearCaches()
  }
  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard gate.isActive, type == .screen, sampleBuffer.isValid,
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
      let status = attachments.first?[.status] as? Int
    else { return }
    let image: CGImage
    if status == SCFrameStatus.idle.rawValue, let latest {
      image = latest
    } else if status == SCFrameStatus.complete.rawValue,
      let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    {
      let source = CIImage(cvPixelBuffer: buffer)
      guard let copy = context.createCGImage(source, from: source.extent) else { return }
      image = copy
    } else {
      latest = nil
      ocr.resetOCR()
      return
    }
    guard gate.isActive else {
      clear()
      return
    }
    latest = image
    if let recording {
      do {
        if try recording.append(image) { self.recording = nil }
      } catch {
        recording.finish("Recording failed: \(error.localizedDescription)")
        self.recording = nil
      }
    }
    guard gate.isActive else {
      clear()
      return
    }
    let output = ocr.read(image, at: ProcessInfo.processInfo.systemUptime)
    if gate.isActive { receive(output.result, output.key, ocr.coverage) } else { clear() }
  }
}

@MainActor
final class Capture: NSObject, SCContentSharingPickerObserver, SCStreamDelegate {
  private let runtime = CaptureRuntime()
  private var reader: FrameReader?
  private var selectedFilter: SCContentFilter?
  private(set) var selectedWindowID: CGWindowID?
  private var currentConnection: StreamConnection?
  private var currentStream: SCStream? { currentConnection?.stream }
  /// Whether a game window is being captured.
  var isCapturing: Bool { currentConnection != nil }
  private var pickerRequested = false
  private var observingPicker = false
  private(set) var enabled = false
  private var diagnosticsEnabled = false
  private(set) var currentSample: DiagnosticSampleKey?
  var diagnosticSessionStarted: ((UUID) -> Void)?
  var diagnosticCoverage: ((UUID, DiagnosticCoverage) -> Void)?
  private let queue = DispatchQueue(label: "Loupe.OCR", qos: .userInitiated)
  var receive: ((Result<CardReading, Error>) -> Void)?
  var status: ((String) -> Void)?
  var didStop: (() -> Void)?
  var recordingStatus: ((String, Bool) -> Void)?

  override init() {
    super.init()
    runtime.ready = { [weak self] in
      self?.status?("Live. Read the artifact in Inventory before opening Enhance.")
    }
    runtime.failed = { [weak self] error in
      guard let self else { return }
      reader = nil
      currentConnection = nil
      didStop?()
      recordingStatus?("Recording stopped.", false)
      if enabled {
        status?("Sharing is unavailable. Choose game window again. \(error.localizedDescription)")
      } else {
        status?(
          "Reader disabled, but macOS could not stop sharing. Stop sharing in macOS. \(error.localizedDescription)"
        )
      }
    }
  }

  func recordSequence() {
    guard enabled, let reader, reader.gate.isActive else {
      recordingStatus?("Share the game window before recording.", false)
      return
    }
    recordingStatus?("Recording 40 game frames locally...", true)
    let token = runtime.generation
    queue.async { [weak self] in
      guard reader.gate.isActive else { return }
      reader.recording = FrameRecording { message in
        Task { @MainActor in
          guard let self, self.runtime.accepts(token) else { return }
          self.recordingStatus?(message, false)
        }
      }
    }
  }

  func setDiagnosticsEnabled(_ value: Bool) {
    diagnosticsEnabled = value
    updateDiagnostics { $0.setEnabled(value) }
  }

  func finishDiagnosticReading(
    _ key: DiagnosticSampleKey, artifact: Artifact?, decision: String, state: DiagnosticState
  ) {
    updateDiagnostics { $0.finish(key, artifact: artifact, decision: decision, state: state) }
  }

  func recordDiagnosticState(_ state: DiagnosticState, key: DiagnosticSampleKey) {
    updateDiagnostics { $0.record(state, key: key) }
  }

  func expireDiagnostics() {
    guard diagnosticsEnabled else { return }
    updateDiagnostics { $0.expire(at: ProcessInfo.processInfo.systemUptime) }
  }

  private func updateDiagnostics(_ update: @escaping @Sendable (inout DiagnosticReader) -> Void) {
    guard let reader, enabled else { return }
    let token = runtime.generation
    queue.async { [weak self] in
      guard reader.gate.isActive else { return }
      update(&reader.ocr)
      let coverage = reader.ocr.coverage
      Task { @MainActor in
        guard let self, self.enabled, self.runtime.accepts(token) else { return }
        self.diagnosticCoverage?(reader.sessionID, coverage)
      }
    }
  }

  func freezeDiagnostics() async throws -> DiagnosticSnapshot {
    guard enabled, let reader, reader.gate.isActive else {
      throw DiagnosticError.invalid(
        "no active shared window; enable the reader and choose game window")
    }
    let token = runtime.generation
    diagnosticsEnabled = false
    let snapshot: DiagnosticSnapshot = try await withCheckedThrowingContinuation { continuation in
      queue.async {
        guard reader.gate.isActive else {
          continuation.resume(
            throwing: DiagnosticError.invalid("capture session ended during freeze"))
          return
        }
        continuation.resume(
          with: Result { try reader.ocr.freeze(at: ProcessInfo.processInfo.systemUptime) })
      }
    }
    guard enabled, runtime.accepts(token), self.reader === reader else {
      throw DiagnosticError.invalid("capture session changed during freeze")
    }
    return snapshot
  }

  func chooseWindow() {
    guard enabled else {
      status?("Enable Loupe before choosing a game window.")
      return
    }
    let picker = SCContentSharingPicker.shared
    if !observingPicker {
      picker.add(self)
      observingPicker = true
    }
    pickerRequested = true
    var config = SCContentSharingPickerConfiguration()
    config.allowedPickerModes = [.singleWindow]
    config.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "io.github.xinding33.loupe"]
    picker.defaultConfiguration = config
    picker.isActive = true
    picker.present(using: .window)
    status?("Select the GeForce NOW game window in the macOS picker.")
  }

  func setEnabled(_ value: Bool) {
    enabled = value
    pickerRequested = false
    replace(value ? selectedFilter : nil)
    if value {
      if selectedFilter == nil {
        status?("Choose game window to share it. Read Inventory again before Enhance.")
      }
    } else {
      SCContentSharingPicker.shared.isActive = false
      status?("Disabled. Capture, OCR, and recording are stopped.")
    }
  }

  func stop() async {
    setEnabled(false)
    await runtime.waitForTransition()
  }

  private func replace(_ filter: SCContentFilter?) {
    currentSample = nil
    didStop?()
    reader = nil
    currentConnection = nil
    recordingStatus?("Recording stopped.", false)
    guard let filter else {
      runtime.replace(with: nil)
      return
    }
    SCContentSharingPicker.shared.isActive = true
    status?("Waiting for a fresh Inventory card. Sharing may need permission again.")
    runtime.replace { [weak self] token in
      guard let self else { throw ArtifactError("Capture closed.") }
      let config = SCStreamConfiguration()
      config.width = Int(filter.contentRect.width * Double(filter.pointPixelScale))
      config.height = Int(filter.contentRect.height * Double(filter.pointPixelScale))
      config.minimumFrameInterval = CMTime(value: 1, timescale: 2)
      config.queueDepth = 3
      config.showsCursor = false
      config.capturesAudio = false
      let sessionID = UUID()
      let reader = try FrameReader(
        sessionID: sessionID, diagnosticsEnabled: self.diagnosticsEnabled
      ) {
        [weak self] result, sample, coverage in
        Task { @MainActor in
          guard let self, self.enabled, self.runtime.accepts(token) else { return }
          self.currentSample = sample
          self.receive?(result)
          self.diagnosticCoverage?(sessionID, coverage)
        }
      }
      let stream = SCStream(filter: filter, configuration: config, delegate: self)
      try stream.addStreamOutput(
        reader, type: .screen, sampleHandlerQueue: self.queue)
      self.reader = reader
      self.diagnosticSessionStarted?(sessionID)
      let connection = StreamConnection(stream: stream, reader: reader, queue: self.queue)
      self.currentConnection = connection
      return connection
    }
  }

  nonisolated func contentSharingPicker(
    _ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?
  ) {
    let streamID = stream.map(ObjectIdentifier.init)
    Task { @MainActor in
      guard enabled,
        pickerRequested || (streamID != nil && streamID == currentStream.map(ObjectIdentifier.init))
      else { return }
      pickerRequested = false
      guard #available(macOS 15.2, *), let window = filter.includedWindows.first,
        filter.includedWindows.count == 1
      else {
        status?("Window tracking requires macOS 15.2 or later and a single shared window.")
        return
      }
      selectedWindowID = window.windowID
      selectedFilter = filter
      replace(filter)
    }
  }
  nonisolated func contentSharingPicker(
    _ picker: SCContentSharingPicker, didCancelFor stream: SCStream?
  ) {
    Task { @MainActor in
      guard enabled, pickerRequested else { return }
      pickerRequested = false
      status?("Window selection canceled. Choose game window to try again.")
    }
  }
  nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
    Task { @MainActor in
      guard enabled, pickerRequested else { return }
      pickerRequested = false
      status?("Window picker failed: \(error.localizedDescription)")
    }
  }
  nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
    let streamID = ObjectIdentifier(stream)
    Task { @MainActor in
      guard enabled, streamID == currentStream.map(ObjectIdentifier.init) else { return }
      currentConnection?.captureEnded()
      replace(nil)
      status?("Capture ended. Choose game window again. \(error.localizedDescription)")
    }
  }
}

@MainActor
private final class StreamConnection: CaptureConnection {
  let stream: SCStream
  let reader: FrameReader
  let queue: DispatchQueue
  private enum State { case starting, running, ended }
  private var state = State.starting

  init(stream: SCStream, reader: FrameReader, queue: DispatchQueue) {
    self.stream = stream
    self.reader = reader
    self.queue = queue
  }

  func start() async throws {
    do {
      try await stream.startCapture()
      guard state != .ended else { throw ArtifactError("Capture ended while starting.") }
      state = .running
    } catch {
      state = .ended
      throw error
    }
  }
  func captureEnded() { state = .ended }
  func invalidate() {
    reader.gate.close()
    queue.async { [reader] in reader.clear() }
  }
  func stop() async throws {
    invalidate()
    if state == .running {
      try await stream.stopCapture()
      state = .ended
    }
    try? stream.removeStreamOutput(reader, type: .screen)
  }
}
