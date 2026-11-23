import CoreGraphics
import Foundation
import LoupeCore
import Testing

@testable import Loupe

private func blankImage() throws -> CGImage {
  let pixels = try DiagnosticPixels(
    width: 1152, height: 768, bytes: Data(repeating: 0, count: 1152 * 768 * 4))
  return try pixels.makeImage()
}

@MainActor
@Test func liveReadTriesTheLastInventoryLayoutFirst() throws {
  let image = try diagnosticInventoryImage()
  var live = LiveCardOCR()
  let first = try live.read(image, at: 1)
  #expect(live.passes == [.enhance, .inventory])
  let second = try live.read(image, at: 1.5)
  #expect(live.passes == [.inventory])
  #expect(second.text == first.text)
  #expect(second.stars == first.stars)
  #expect(second.confidence == first.confidence)
  #expect(!second.isEnhancement)
}

@MainActor
@Test func liveReadFallsBackWhenTheInventoryReadFindsNoCard() throws {
  var live = LiveCardOCR()
  _ = try live.read(diagnosticInventoryImage(), at: 1)
  let blank = try blankImage()
  var fresh = LiveCardOCR()
  let expected = #expect(throws: ArtifactError.self) { try fresh.read(blank, at: 1.5) }
  let actual = #expect(throws: ArtifactError.self) { try live.read(blank, at: 1.5) }
  // The Inventory read ran first and its error is reused, not read again.
  #expect(live.passes == [.inventory, .enhance])
  #expect(actual?.localizedDescription == expected?.localizedDescription)
  // No card was read, so the next frame goes back to the usual order.
  _ = try live.read(diagnosticInventoryImage(), at: 2)
  #expect(live.passes == [.enhance, .inventory])
}

@MainActor
@Test func liveReadStillReadsEnhanceRightAfterInventory() throws {
  let inventory = try diagnosticInventoryImage()
  let enhance = try diagnosticEnhanceImage()
  var live = LiveCardOCR()
  _ = try live.read(inventory, at: 1)
  _ = try live.read(inventory, at: 1.5)
  #expect(live.passes == [.inventory])
  // The first Enhance frame is read as Enhance; its fields confirm on the next one, as before.
  let trace = DiagnosticOCRTrace()
  #expect(throws: ArtifactError.self) { try live.read(enhance, at: 2, diagnostics: trace) }
  #expect(live.passes == [.inventory, .enhance])
  #expect(trace.mode == .enhance)
  #expect(trace.inputs.map(\.metadata.kind) == [.enhanceHeading, .enhanceStats])
  #expect(trace.inputs.allSatisfy { $0.metadata.isExactOCRInput })
  // Enhance keeps the usual order on the next frame.
  let reading = try live.read(enhance, at: 2.5)
  #expect(live.passes == [.enhance])
  #expect(reading.isEnhancement)
}

@MainActor
@Test func liveReadTracesKeepTheirShapeWhenInventoryGoesFirst() throws {
  let inventory = try diagnosticInventoryImage()
  let enhance = try diagnosticEnhanceImage()
  var reader = try DiagnosticReader(sessionID: UUID())
  reader.setEnabled(true)
  _ = reader.read(inventory, at: 1)
  _ = reader.read(inventory, at: 1.5)
  _ = reader.read(try blankImage(), at: 2)
  _ = reader.read(inventory, at: 2.5)
  _ = reader.read(inventory, at: 3)
  _ = reader.read(enhance, at: 3.5)
  _ = reader.read(enhance, at: 4)
  let samples = reader.buffer.samples
  #expect(samples.count == 7)
  #expect(
    samples.map(\.metadata.mode) == Array(repeating: .inventory, count: 5) + [.enhance, .enhance])
  // An Inventory sample holds its card crop whichever order found it; the blank one holds none.
  for index in [0, 1, 3, 4] {
    #expect(samples[index].inputs.map(\.metadata.kind) == [.inventoryCard])
    #expect(
      samples[index].inputs.first?.metadata.cropBounds
        == samples[0].inputs.first?.metadata.cropBounds)
    #expect(samples[index].metadata.assembledText == samples[0].metadata.assembledText)
  }
  #expect(samples[2].inputs.isEmpty)
  #expect(reader.coverage.issue == nil)
  // Enhance samples hold exactly the two crops replay needs.
  for sample in samples[5...] {
    #expect(sample.inputs.map(\.metadata.kind) == [.enhanceHeading, .enhanceStats])
    #expect(sample.inputs.allSatisfy { $0.metadata.isExactOCRInput })
  }
  var replay = LiveCardOCR()
  _ = try? replay.replay(samples[5])
  #expect(try replay.replay(samples[6]).isEnhancement)
}
