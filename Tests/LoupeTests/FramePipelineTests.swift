import AppKit
import CoreImage
import CoreVideo
import LoupeCore
import Testing

@testable import Loupe

/// A BGRA buffer like the capture stream's, holding `image`. `padding` adds bytes to every row.
private func pixelBuffer(
  _ image: CGImage, format: OSType = kCVPixelFormatType_32BGRA, padding: Int = 0
) throws -> CVPixelBuffer {
  var created: CVPixelBuffer?
  if padding == 0 {
    let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
    CVPixelBufferCreate(nil, image.width, image.height, format, attributes, &created)
  } else {
    let bytesPerRow = image.width * 4 + padding
    let memory = UnsafeMutableRawPointer.allocate(
      byteCount: bytesPerRow * image.height, alignment: 64)
    memory.initializeMemory(as: UInt8.self, repeating: 0x5A, count: bytesPerRow * image.height)
    CVPixelBufferCreateWithBytes(
      nil, image.width, image.height, format, memory, bytesPerRow,
      { _, base in base?.deallocate() }, nil, nil, &created)
  }
  let buffer = try #require(created)
  CVPixelBufferLockBaseAddress(buffer, [])
  defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
  let order =
    format == kCVPixelFormatType_32BGRA
    ? CGBitmapInfo.byteOrder32Little.rawValue : CGBitmapInfo.byteOrder32Big.rawValue
  let context = try #require(
    CGContext(
      data: CVPixelBufferGetBaseAddress(buffer), width: image.width, height: image.height,
      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | order))
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
@Test func pipelineReusesAnUnchangedFrameAndReadsAOneDigitChange() throws {
  let pipeline = try Driver()
  let card = try pixelBuffer(diagnosticInventoryImage())
  let first = try #require(pipeline.frame(card, at: 1)).result.get()
  #expect(pipeline.ocr.visionReads == 1)
  // A fresh capture of the same screen gives the read's outcome without Vision.
  let repeated = try pixelBuffer(diagnosticInventoryImage())
  let again = try #require(pipeline.frame(repeated, at: 1.2)).result.get()
  #expect(pipeline.ocr.visionReads == 1)
  var plain = LiveCardOCR()
  _ = try plain.read(copied(card), at: 1)
  let expected = try plain.read(copied(repeated), at: 1.2)
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
}

@MainActor
@Test func pipelineConfirmsAnUnchangedEnhanceFrameWithoutASecondVisionPass() throws {
  let pipeline = try Driver()
  let enhance = try pixelBuffer(diagnosticEnhanceImage())
  let first = try #require(pipeline.frame(enhance, at: 1))
  // One observation can't confirm the fields.
  #expect(throws: ArtifactError.self) { try first.result.get() }
  let second = try #require(pipeline.frame(pixelBuffer(diagnosticEnhanceImage()), at: 1.2))
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
  _ = pipeline.frame(card, at: 1.2)
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
  // With the buffer off again, the last read is reused.
  pipeline.ocr.setEnabled(false)
  let reused = try #require(pipeline.frame(card, at: 2))
  #expect(reused.key == nil)
  #expect(pipeline.ocr.visionReads == 3)
  #expect(try reused.result.get().text == deliveries[2].result.get().text)
}

@MainActor
@Test func pipelineReadsFramesItCannotCompare() throws {
  let pipeline = try Driver()
  let image = try diagnosticInventoryImage()
  // An unexpected pixel format can't be sampled, so its frames always count as changed.
  let argb = try pixelBuffer(image, format: kCVPixelFormatType_32ARGB)
  #expect(FrameSamples(argb) == nil)
  _ = pipeline.frame(argb, at: 1)
  _ = pipeline.frame(argb, at: 1.2)
  #expect(pipeline.ocr.visionReads == 2)
  #expect(pipeline.frame(argb, at: 1.4) == nil)
  // A window of another size doesn't match either.
  let sized = try Driver()
  let card = try pixelBuffer(image)
  _ = sized.frame(card, at: 1)
  let canvas = try #require(
    CGContext(
      data: nil, width: image.width + 8, height: image.height, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  canvas.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  _ = sized.frame(try pixelBuffer(#require(canvas.makeImage())), at: 1.2)
  #expect(sized.ocr.visionReads == 2)
}

@MainActor
@Test func captureBufferSamplesSkipRowPadding() throws {
  let image = try diagnosticInventoryImage()
  let plain = try #require(FrameSamples(pixelBuffer(image)))
  let padded = try pixelBuffer(image, padding: 72)
  #expect(CVPixelBufferGetBytesPerRow(padded) == image.width * 4 + 72)
  let samples = try #require(FrameSamples(padded))
  #expect(samples.values == plain.values)
  #expect(!samples.differs(from: plain))
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

// MARK: Sensitivity at the game's scale

/// A frame like the game's at `width`: an Inventory card with two substat lines and a level tag,
/// at the sizes measured on a 5,120-pixel-wide capture, softened as streamed video is. `shift`
/// moves the text against the sample grid.
@MainActor
private func gameFrame(width: Int, lines: [String], shift: Double) throws -> CVPixelBuffer {
  let scale = Double(width) / 5120
  let height = Int((3414 * scale).rounded())
  let context = try #require(
    CGContext(
      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
  context.setFillColor(CGColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  context.setFillColor(CGColor(red: 0.91, green: 0.88, blue: 0.83, alpha: 1))
  context.fill(CGRect(x: 2560 * scale, y: 300 * scale, width: 1280 * scale, height: 2900 * scale))
  context.setFillColor(CGColor(red: 0.23, green: 0.25, blue: 0.31, alpha: 1))
  context.fill(
    CGRect(
      x: (2640 + shift) * scale, y: (1884 - shift) * scale, width: 120 * scale,
      height: 64 * scale))
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
  // The level tag's digits are about 34 pixels tall at this width, substat values about 48.
  (lines[0] as NSString).draw(
    at: NSPoint(x: (2650 + shift) * scale, y: (1887 - shift) * scale),
    withAttributes: [
      .font: NSFont.systemFont(ofSize: 48 * scale, weight: .bold), .foregroundColor: NSColor.white,
    ])
  for (index, line) in lines.dropFirst().enumerated() {
    (line as NSString).draw(
      at: NSPoint(x: (2680 + shift) * scale, y: (1654 - 100 * Double(index) - shift) * scale),
      withAttributes: [
        .font: NSFont.systemFont(ofSize: 64 * scale, weight: .bold),
        .foregroundColor: NSColor(calibratedRed: 0.24, green: 0.26, blue: 0.31, alpha: 1),
      ])
  }
  NSGraphicsContext.restoreGraphicsState()
  let sharp = try #require(context.makeImage())
  let soft = CIImage(cgImage: sharp).clampedToExtent().applyingGaussianBlur(sigma: 2 * scale)
    .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
  return try pixelBuffer(#require(CIContext().createCGImage(soft, from: soft.extent)))
}

@MainActor
@Test(arguments: [5120, 2560])
func oneDigitChangesOnAGameSizedFrameAreCaught(_ width: Int) throws {
  let scale = Double(width) / 5120
  let step = Double(FrameSamples.step(width: width, height: Int((3414 * scale).rounded())))
  // Each frame changes one digit of the one before: the changes named in the design, and the
  // closest pairs of digits found by trying every pair offline.
  let frames = [
    ["+0", "DEF+5.8%", "Elemental Mastery+16"],
    ["+0", "DEF+5.3%", "Elemental Mastery+16"],
    ["+0", "DEF+5.3%", "Elemental Mastery+19"],
    ["+4", "DEF+5.3%", "Elemental Mastery+19"],
    ["+5", "DEF+5.3%", "Elemental Mastery+19"],
    ["+6", "DEF+5.3%", "Elemental Mastery+19"],
    ["+8", "DEF+5.3%", "Elemental Mastery+19"],
  ]
  for shift in [0, step * 2.5 / scale] {
    var previous: FrameSamples?
    for lines in frames {
      let samples = try #require(FrameSamples(gameFrame(width: width, lines: lines, shift: shift)))
      if let previous {
        let difference = try #require(samples.largestDifference(from: previous))
        // Every pair of digits measured at least 10.6 offline, over three times the threshold.
        #expect(difference >= 2 * FrameSamples.threshold, "\(lines) at \(width) shifted \(shift)")
      }
      previous = samples
    }
    let again = try #require(FrameSamples(gameFrame(width: width, lines: frames[6], shift: shift)))
    #expect(again.largestDifference(from: try #require(previous)) == 0)
  }
}
