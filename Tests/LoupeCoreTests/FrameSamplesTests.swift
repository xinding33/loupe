import Foundation
import LoupeCore
import Testing

/// A BGRA frame with padded rows; the padding holds bytes the samples must never read.
private struct Frame {
  let width: Int
  let height: Int
  let bytesPerRow: Int
  var bytes: [UInt8]

  init(width: Int, height: Int, padding: Int = 0, fill: UInt8 = 120) {
    self.width = width
    self.height = height
    bytesPerRow = width * 4 + padding
    bytes = [UInt8](repeating: fill, count: bytesPerRow * height)
    for y in 0..<height {
      for i in width * 4..<bytesPerRow { bytes[y * bytesPerRow + i] = 0xEE }
    }
  }

  subscript(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
    get {
      let i = y * bytesPerRow + x * 4
      return (bytes[i], bytes[i + 1], bytes[i + 2])
    }
    set {
      let i = y * bytesPerRow + x * 4
      (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]) = (
        newValue.0, newValue.1, newValue.2, 255
      )
    }
  }

  /// Every pixel in a rectangle shifted by `amount` per channel.
  mutating func change(x: Range<Int>, y: Range<Int>, by amount: Int) {
    for row in y {
      for column in x {
        let (b, g, r) = self[column, row]
        func shift(_ v: UInt8) -> UInt8 { UInt8(clamping: Int(v) + amount) }
        self[column, row] = (shift(b), shift(g), shift(r))
      }
    }
  }

  func samples(step: Int? = nil) -> FrameSamples? {
    bytes.withUnsafeBytes {
      FrameSamples(pixels: $0, width: width, height: height, bytesPerRow: bytesPerRow, step: step)
    }
  }
}

@Test func frameSampleSpacingScalesWithTheWindow() {
  #expect(FrameSamples.step(width: 5120, height: 3414) == 4)
  #expect(FrameSamples.step(width: 2560, height: 1707) == 2)
  #expect(FrameSamples.step(width: 3840, height: 2160) == 3)
  // A wide window's picture is scaled to its height.
  #expect(FrameSamples.step(width: 5120, height: 2160) == 3)
  #expect(FrameSamples.step(width: 1280, height: 720) == 1)
  #expect(FrameSamples.step(width: 640, height: 400) == 1)
  let samples = Frame(width: 2560, height: 1707).samples()
  #expect(samples?.step == 2)
  #expect(samples?.columns == 1280)
  #expect(samples?.rows == 853)
}

@Test func frameSamplesSkipRowPadding() throws {
  var padded = Frame(width: 320, height: 200, padding: 48)
  var plain = Frame(width: 320, height: 200)
  padded.change(x: 10..<90, y: 20..<60, by: 70)
  plain.change(x: 10..<90, y: 20..<60, by: 70)
  let before = try #require(padded.samples())
  #expect(before.values == plain.samples()?.values)
  // Whatever the padding holds, the frame hasn't changed.
  for y in 0..<padded.height {
    for i in padded.width * 4..<padded.bytesPerRow { padded.bytes[y * padded.bytesPerRow + i] = 0 }
  }
  let after = try #require(padded.samples())
  #expect(after.largestDifference(from: before) == 0)
  #expect(!after.differs(from: before))
}

@Test func frameSamplesRejectAFrameThatDoesNotFitItsBytes() {
  let bytes = [UInt8](repeating: 0, count: 100 * 4 * 10)
  bytes.withUnsafeBytes {
    #expect(FrameSamples(pixels: $0, width: 100, height: 11, bytesPerRow: 400) == nil)
    #expect(FrameSamples(pixels: $0, width: 100, height: 10, bytesPerRow: 399) == nil)
    #expect(FrameSamples(pixels: $0, width: 0, height: 10, bytesPerRow: 400) == nil)
    #expect(FrameSamples(pixels: $0, width: 100, height: 10, bytesPerRow: 400) != nil)
  }
}

@Test func frameSamplesTolerateStreamingNoise() throws {
  let still = Frame(width: 1280, height: 720)
  var noisy = still
  // Every channel of every pixel off by up to 2, more than captures of a still screen differed.
  var seed: UInt32 = 1
  for index in noisy.bytes.indices where index % 4 != 3 {
    seed = seed &* 1_664_525 &+ 1_013_904_223
    noisy.bytes[index] = UInt8(Int(noisy.bytes[index]) + Int(seed >> 24) % 5 - 2)
  }
  let a = try #require(still.samples())
  let b = try #require(noisy.samples())
  let difference = try #require(b.largestDifference(from: a))
  #expect(difference > 0)
  #expect(difference < FrameSamples.threshold / 2)
  #expect(!b.differs(from: a))
}

@Test(arguments: [(0, 0), (3, 3), (5, 2), (7, 7), (1, 6)])
func frameSamplesCatchAChangeSmallerThanACellWhereverItFalls(_ offset: (Int, Int)) throws {
  // 1,280 x 720 samples one pixel apart; a 3 x 3 patch is under a cell and can straddle four.
  let still = Frame(width: 1280, height: 720)
  let base = 400
  var changed = still
  changed.change(
    x: base + offset.0..<base + offset.0 + 3, y: base + offset.1..<base + offset.1 + 3, by: 40)
  let a = try #require(still.samples())
  let b = try #require(changed.samples())
  // 9 samples x 40 over the 64 samples of a square, whichever cells the patch spans.
  #expect(try #require(b.largestDifference(from: a)) >= 9 * 40 / 64.0)
  #expect(b.differs(from: a))
}

@Test func frameSamplesCatchAChangeAtTheFrameEdge() throws {
  // 1,283 columns leave a partial cell at the right; the corner patch lands in it.
  let still = Frame(width: 1283, height: 721)
  var changed = still
  changed.change(x: 1280..<1283, y: 718..<721, by: 60)
  let a = try #require(still.samples())
  let b = try #require(changed.samples())
  #expect(b.differs(from: a))
  var top = still
  top.change(x: 0..<2, y: 0..<2, by: 60)
  #expect(top.samples()?.differs(from: a) == true)
}

@Test func framesOfAnotherSizeOrSpacingAlwaysDiffer() throws {
  let a = try #require(Frame(width: 1280, height: 720).samples())
  let b = try #require(Frame(width: 1280, height: 721).samples())
  let c = try #require(Frame(width: 2560, height: 1440).samples(step: 1))
  let d = try #require(Frame(width: 2560, height: 1440).samples())
  #expect(a.largestDifference(from: b) == nil)
  #expect(a.differs(from: b))
  #expect(c.largestDifference(from: d) == nil)
  #expect(c.differs(from: d))
  #expect(a.largestDifference(from: a) == 0)
  #expect(!a.differs(from: a))
}
