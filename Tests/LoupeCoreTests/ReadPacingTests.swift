import Foundation
import LoupeCore
import Testing

/// Drives `ReadPacing` the way the frame pipeline does: a read or reuse delivers an outcome.
private struct Pacer {
  var pacing = ReadPacing<String>()
  var reads: [Double] = []
  var reuses: [Double] = []
  /// What a read of the latest frame gives.
  var showing = "no card"

  @discardableResult
  mutating func frame(_ time: Double, matches: Bool = false, reusable: Bool = true)
    -> ReadPacing<String>.Decision
  {
    record(pacing.frame(at: time, reusable: matches && reusable), at: time)
  }

  @discardableResult
  mutating func idle(_ time: Double, reusable: Bool = true) -> ReadPacing<String>.Decision {
    record(pacing.idle(at: time, reusable: reusable), at: time)
  }

  @discardableResult
  mutating func tick(_ time: Double) -> ReadPacing<String>.Decision {
    record(pacing.tick(at: time), at: time)
  }

  private mutating func record(_ decision: ReadPacing<String>.Decision, at time: Double)
    -> ReadPacing<String>.Decision
  {
    switch decision {
    case .read:
      reads.append(time)
      pacing.delivered(showing)
    case .reuse:
      reuses.append(time)
      pacing.delivered(showing)
    case .hold, .ignore: break
    }
    return decision
  }
}

/// Times to the hundredth, since frame times are sums of fifths of a second.
private func rounded(_ times: [Double]) -> [Double] { times.map { ($0 * 100).rounded() / 100 } }
private func rounded(_ time: Double?) -> Double? { time.map { ($0 * 100).rounded() / 100 } }

/// Frame times five a second, from `start`.
private func times(from start: Double, count: Int) -> [Double] {
  (0..<count).map { start + Double($0) * 0.2 }
}

@Test func pacingReadsAStillScreenOnceThenEveryTwoSeconds() {
  var pacer = Pacer()
  #expect(pacer.frame(0) == .read)
  for time in times(from: 0.2, count: 9) {
    #expect(pacer.frame(time, matches: true) == .reuse)
    #expect(pacer.idle(time + 0.1) == .reuse)
  }
  #expect(pacer.reads == [0])
  // A change the comparison missed can't keep an old reading up for long.
  for time in times(from: 2, count: 41) {
    pacer.frame(time, matches: true)
    pacer.idle(time + 0.1)
  }
  #expect(rounded(pacer.reads) == [0, 2, 4, 6, 8, 10])
  #expect(pacer.reuses.count == 95)
  #expect(pacer.pacing.deadline == nil)
}

@Test func pacingRefreshesAStillScreenFromAnIdleFrame() {
  var pacer = Pacer()
  #expect(pacer.frame(0) == .read)
  #expect(pacer.idle(1.9) == .reuse)
  #expect(pacer.idle(2.1) == .read)
  #expect(pacer.idle(2.3) == .reuse)
}

@Test func pacingReadsAChangingScreenTwiceASecond() {
  var pacer = Pacer()
  for time in times(from: 0, count: 50) {
    if let deadline = pacer.pacing.deadline, deadline <= time { pacer.tick(deadline) }
    pacer.frame(time)
  }
  // The first two settle the reading; then one read every half second, the timer reading the
  // held frame on time.
  #expect(rounded(Array(pacer.reads.prefix(4))) == [0, 0.2, 0.7, 1.2])
  #expect(pacer.reads.count == 21)
  for (earlier, later) in zip(pacer.reads.dropFirst(), pacer.reads.dropFirst(2)) {
    #expect(later - earlier >= ReadPacing<String>.interval - 0.011)
  }
  #expect(pacer.reuses.isEmpty)
}

@Test func pacingReadsANewCardOnTheFirstFrameAndConfirmsItOnTheNext() {
  var pacer = Pacer()
  pacer.frame(0)
  pacer.frame(0.2, matches: true)
  // Settled on a still screen; a card appears long after the last read.
  pacer.showing = "card"
  #expect(pacer.frame(3) == .read)
  // The reading changed, so the next frame isn't held: it matches, and repeats the card.
  #expect(pacer.frame(3.2, matches: true) == .reuse)
  #expect(pacer.reads == [0, 3])
  #expect(pacer.reuses == [0.2, 3.2])
}

@Test func pacingReadsChangedFramesAtOnceWhileTheReadingIsUnsettled() {
  var pacer = Pacer()
  for (index, time) in times(from: 0, count: 3).enumerated() {
    pacer.showing = "frame \(index)"
    #expect(pacer.frame(time) == .read)
  }
  // Two equal outcomes settle it; the next change waits.
  pacer.frame(0.6, matches: true)
  #expect(pacer.frame(0.8) == .hold)
  #expect(rounded(pacer.pacing.deadline) == 0.9)
  #expect(pacer.reads.count == 3)
}

@Test func pacingLimitsFastReadsWhenTheReadingNeverSettles() {
  var pacer = Pacer()
  var index = 0
  for time in times(from: 0, count: 26) {
    if let deadline = pacer.pacing.deadline, deadline <= time {
      index += 1
      pacer.showing = "frame \(index)"
      pacer.tick(deadline)
    }
    index += 1
    pacer.showing = "frame \(index)"
    pacer.frame(time)
  }
  // The first read, a burst of four fast ones, then two a second for as long as it flickers.
  #expect(Array(rounded(pacer.reads).prefix(8)) == [0, 0.2, 0.4, 0.6, 0.8, 1.3, 1.8, 2.3])
  #expect(pacer.reads.count == 13)

  // Settling earns the next change a fresh burst.
  pacer.frame(5.3)
  pacer.frame(5.4, matches: true)
  pacer.showing = "a new card"
  #expect(pacer.frame(5.6) == .hold)
  #expect(pacer.tick(5.8) == .read)
  pacer.showing = "the card, read again"
  #expect(pacer.frame(6.0) == .read)
}

@Test func pacingHoldsAChangedFrameAndReadsItOnTimeThroughIdleFrames() {
  var pacer = Pacer()
  pacer.frame(0)
  pacer.frame(0.2, matches: true)
  pacer.showing = "card"
  #expect(pacer.frame(0.3) == .hold)
  #expect(pacer.pacing.deadline == 0.5)
  // Idle frames repeat the held frame; it is read once due, not lost.
  #expect(pacer.idle(0.4) == .hold)
  #expect(pacer.idle(0.5) == .read)
  #expect(pacer.reads == [0, 0.5])
  #expect(pacer.pacing.deadline == nil)
  // The new reading is unsettled, so the next idle frame repeats it without Vision.
  #expect(pacer.idle(0.7) == .reuse)
}

@Test func pacingTimerReadsAHeldFrameWhenNoFrameFollows() {
  var pacer = Pacer()
  pacer.frame(0)
  pacer.frame(0.2, matches: true)
  #expect(pacer.frame(0.4) == .hold)
  #expect(pacer.tick(0.45) == .hold)
  #expect(pacer.tick(0.5) == .read)
  #expect(pacer.tick(1) == .ignore)
  #expect(pacer.reads == [0, 0.5])
}

@Test func pacingDropsAHeldFrameWhenTheScreenReturnsToTheReadFrame() {
  var pacer = Pacer()
  pacer.frame(0)
  pacer.frame(0.2, matches: true)
  #expect(pacer.frame(0.3) == .hold)
  #expect(pacer.frame(0.4, matches: true) == .reuse)
  #expect(pacer.pacing.deadline == nil)
  #expect(pacer.tick(0.5) == .ignore)
  #expect(pacer.reads == [0])
}

@Test func pacingReadsAFrameThatCannotBeReused() {
  var pacer = Pacer()
  pacer.frame(0)
  pacer.frame(0.2, matches: true)
  // The pixels match, but the last read's outcome can't stand in for them.
  #expect(pacer.frame(0.4, matches: true, reusable: false) == .hold)
  #expect(pacer.frame(0.6, matches: true, reusable: false) == .read)
}

@Test func pacingWithDiagnosticsReadsAStillScreenTwiceASecond() {
  // Buffering diagnostics, nothing is reusable, so a report holds real OCR inputs.
  var pacer = Pacer()
  pacer.frame(0, matches: true, reusable: false)
  for time in times(from: 0.2, count: 20) { pacer.idle(time, reusable: false) }
  #expect(pacer.reuses.isEmpty)
  // Idle frames repeat the read frame: read again at once while unsettled, then every 0.6 s
  // without the timer, which the pipeline sets for `deadline`.
  #expect(rounded(pacer.reads) == [0, 0.2, 0.8, 1.4, 2.0, 2.6, 3.2, 3.8])
  #expect(rounded(pacer.pacing.deadline) == 4.3)
}

@Test func pacingIgnoresIdleFramesBeforeTheFirstFrame() {
  var pacer = Pacer()
  #expect(pacer.idle(0) == .ignore)
  #expect(pacer.tick(1) == .ignore)
  #expect(pacer.frame(1.2) == .read)
}

@Test func pacingCountsAFrameJustShortOfTheIntervalAsDue() {
  var pacer = Pacer()
  pacer.frame(0)
  pacer.frame(0.1, matches: true)
  #expect(pacer.frame(0.48) == .hold)
  #expect(pacer.frame(0.495) == .read)
}
