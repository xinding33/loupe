import AppKit
import CoreImage
import CoreVideo
import LoupeCore
import Testing

@testable import Loupe

/// A BGRA buffer like the capture stream's, holding `image`.
private func pixelBuffer(_ image: CGImage) throws -> CVPixelBuffer {
  var created: CVPixelBuffer?
  let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
  CVPixelBufferCreate(
    nil, image.width, image.height, kCVPixelFormatType_32BGRA, attributes, &created)
  let buffer = try #require(created)
  CVPixelBufferLockBaseAddress(buffer, [])
  defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
  let context = try #require(
    CGContext(
      data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue))
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  return buffer
}

/// The image the pipeline reads for a buffer.
private func copied(_ buffer: CVPixelBuffer) throws -> CGImage {
  let source = CIImage(cvPixelBuffer: buffer)
  return try #require(CIContext().createCGImage(source, from: source.extent))
}

/// Drives a pipeline as `FrameReader` does, with explicit frame times.
private final class Driver {
  var pipeline: FramePipeline

  init(buffering: Bool = false) throws {
    var ocr = try DiagnosticReader(sessionID: UUID())
    ocr.setEnabled(buffering)
    pipeline = FramePipeline(ocr: ocr)
  }

  var ocr: DiagnosticReader {
    get { pipeline.ocr }
    set { pipeline.ocr = newValue }
  }
  var hasFrame: Bool { pipeline.hasFrame }
  var deadline: TimeInterval? { pipeline.deadline }

  func frame(_ buffer: CVPixelBuffer, at time: TimeInterval) -> FrameDelivery? {
    pipeline.show(buffer)
    return pipeline.complete(at: time)
  }
  func idle(at time: TimeInterval) -> FrameDelivery? { pipeline.idle(at: time) }
  func tick(at time: TimeInterval) -> FrameDelivery? { pipeline.tick(at: time) }
  func image() -> CGImage? { pipeline.image() }
  func reset() { pipeline.reset() }
  func clear() { pipeline.clear() }
}

@MainActor
@Test func pipelineReusesARepeatedFrameAndReadsEveryNewOne() throws {
  let pipeline = try Driver()
  let card = try pixelBuffer(diagnosticInventoryImage())
  let first = try #require(pipeline.frame(card, at: 1)).result.get()
  #expect(pipeline.ocr.visionReads == 1)
  // A frame the stream reports as a repeat gives the read's outcome without Vision.
  let again = try #require(pipeline.idle(at: 1.2)).result.get()
  #expect(pipeline.ocr.visionReads == 1)
  var plain = LiveCardOCR()
  let expected = try plain.read(copied(card), at: 1)
  for reading in [first, again] {
    #expect(reading.text == expected.text)
    #expect(reading.stars == expected.stars)
    #expect(!reading.isEnhancement)
  }
  #expect(again.text.contains("DEF+16"))

  // One digit of one substat changes. The reading has settled, so it's read half a second after
  // the last read.
  let changed = try pixelBuffer(diagnosticInventoryImage(replacing: ["DEF+16": "DEF+19"]))
  #expect(pipeline.frame(changed, at: 1.4) == nil)
  #expect(pipeline.deadline == 1.5)
  let read = try #require(pipeline.tick(at: 1.5)).result.get()
  #expect(pipeline.ocr.visionReads == 2)
  #expect(read.text.contains("DEF+19"))
  #expect(!read.text.contains("DEF+16"))

  // A new capture is read even when it shows the same screen: pixels that look alike can read
  // differently.
  let same = try pixelBuffer(diagnosticInventoryImage(replacing: ["DEF+16": "DEF+19"]))
  #expect(try #require(pipeline.frame(same, at: 1.7)).result.get().text.contains("DEF+19"))
  #expect(pipeline.ocr.visionReads == 3)
}

@MainActor
@Test func pipelineConfirmsARepeatedEnhanceFrameWithoutASecondVisionPass() throws {
  let pipeline = try Driver()
  let enhance = try pixelBuffer(diagnosticEnhanceImage())
  let first = try #require(pipeline.frame(enhance, at: 1))
  // One observation can't confirm the fields.
  #expect(throws: ArtifactError.self) { try first.result.get() }
  let second = try #require(pipeline.idle(at: 1.2))
  let reading = try second.result.get()
  #expect(reading.isEnhancement)
  #expect(pipeline.ocr.visionReads == 1)
  // The same as Vision reading those pixels twice.
  var plain = LiveCardOCR()
  let image = try copied(enhance)
  #expect(throws: ArtifactError.self) { try plain.read(image, at: 1) }
  let expected = try plain.read(image, at: 1.2)
  #expect(reading.text == expected.text)
  #expect(reading.confidence == expected.confidence)
  // An idle frame repeats it, and confirmation keeps holding.
  let idle = try #require(pipeline.idle(at: 1.4)).result.get()
  #expect(idle.text == expected.text)
  #expect(pipeline.ocr.visionReads == 1)
}

@MainActor
@Test func pipelineReadsAHeldFrameThroughIdleFramesAndSnapshotsIt() throws {
  let pipeline = try Driver()
  let card = try pixelBuffer(diagnosticInventoryImage())
  _ = pipeline.frame(card, at: 1)
  _ = pipeline.idle(at: 1.2)
  let changed = try pixelBuffer(diagnosticInventoryImage(replacing: ["HP+209": "HP+299"]))
  #expect(pipeline.frame(changed, at: 1.3) == nil)
  // A snapshot now saves the held frame, not the frame last read.
  let snapshot = try #require(pipeline.image())
  let held = try copied(changed)
  #expect(snapshot.dataProvider?.data as Data? == held.dataProvider?.data as Data?)
  #expect(snapshot.dataProvider?.data as Data? != (try copied(card)).dataProvider?.data as Data?)
  // Idle frames repeat the held frame until it's due.
  #expect(pipeline.idle(at: 1.4) == nil)
  let read = try #require(pipeline.idle(at: 1.5)).result.get()
  #expect(read.text.contains("HP+299"))
  #expect(pipeline.ocr.visionReads == 2)
}

@MainActor
@Test func pipelineResetDropsTheLastRead() throws {
  let pipeline = try Driver()
  let card = try pixelBuffer(diagnosticInventoryImage())
  _ = pipeline.frame(card, at: 1)
  pipeline.reset()
  #expect(!pipeline.hasFrame)
  #expect(!pipeline.ocr.canReuse)
  #expect(pipeline.ocr.visionReads == 0)
  #expect(try #require(pipeline.frame(card, at: 1.2)).result.get().text.contains("DEF+16"))
  #expect(pipeline.ocr.visionReads == 1)
  pipeline.clear()
  #expect(!pipeline.hasFrame)
  #expect(try #require(pipeline.frame(card, at: 1.4)).result.get().text.contains("DEF+16"))
  #expect(pipeline.ocr.visionReads == 1)
}

@MainActor
@Test func pipelineReadsEveryFrameWhileBufferingDiagnostics() throws {
  let pipeline = try Driver(buffering: true)
  let card = try pixelBuffer(diagnosticInventoryImage())
  var deliveries: [FrameDelivery] = []
  for time in [1, 1.2, 1.4, 1.6, 1.8] {
    if let delivery = pipeline.frame(card, at: time) { deliveries.append(delivery) }
  }
  // Read at once until the reading settles, then twice a second, never reused.
  #expect(deliveries.count == 3)
  #expect(pipeline.ocr.visionReads == 3)
  #expect(deliveries.allSatisfy { $0.key != nil })
  let samples = pipeline.ocr.buffer.samples
  #expect(samples.map(\.metadata.time) == [1, 1.2, 1.8])
  #expect(samples.map(\.metadata.id) == deliveries.compactMap(\.key?.id))
  for sample in samples {
    #expect(sample.metadata.mode == .inventory)
    #expect(sample.inputs.map(\.metadata.kind) == [.inventoryCard])
  }
  #expect(deliveries.last?.coverage.count == 3)
  // With the buffer off again, a repeated frame reuses the last read.
  pipeline.ocr.setEnabled(false)
  let reused = try #require(pipeline.idle(at: 2))
  #expect(reused.key == nil)
  #expect(pipeline.ocr.visionReads == 3)
  #expect(try reused.result.get().text == deliveries[2].result.get().text)
}

@Test func recordingKeepsTwoFramesASecond() throws {
  let folder = FileManager.default.temporaryDirectory.appending(
    path: "Loupe-Recording-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: folder) }
  let recording = FrameRecording(folder: folder) { _, _ in }
  let image = try DiagnosticPixels(width: 1, height: 1, bytes: Data([0, 0, 0, 255])).makeImage()
  var kept: [Double] = []
  for index in 0..<50 {
    let time = 100 + Double(index) * 0.2
    if recording.wants(at: time) {
      _ = try recording.append(image, at: time)
      kept.append(time)
    }
  }
  #expect(kept.count == 20)
  #expect(recording.count == 20)
  for (earlier, later) in zip(kept, kept.dropFirst()) { #expect(later - earlier >= 0.39) }
  // After a gap the next frame is kept at once, and the one after waits again.
  #expect(recording.wants(at: 200))
  _ = try recording.append(image, at: 200)
  #expect(!recording.wants(at: 200.2))
}
