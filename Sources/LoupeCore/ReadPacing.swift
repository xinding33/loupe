import Foundation

/// Decides, frame by frame, whether to run OCR. Frames arrive five times a second. A new frame
/// is read at once while the reading is unsettled, and otherwise held until half a second after
/// the last read, so a settled screen is still read only twice a second. A frame the stream
/// reports as a repeat of one already read gets that read's outcome again.
///
/// Two limits keep a mistake small. A reading that never settles gets only a short burst of fast
/// reads. And a screen that only repeats is read again every two seconds.
public struct ReadPacing<Outcome: Equatable> {
  public enum Decision: Equatable {
    /// Read the latest frame.
    case read
    /// Deliver the last read's outcome again.
    case reuse
    /// Keep the latest frame unread; it's due at `deadline`.
    case hold
    /// Nothing to do.
    case ignore
  }

  /// The longest a changed frame waits once the reading has settled.
  public static var interval: TimeInterval { 0.5 }
  /// The longest repeats of a read frame go on taking its outcome.
  public static var refresh: TimeInterval { 2 }
  /// Reads in a row that may come sooner than `interval` while the reading is unsettled. A new
  /// card needs one and an Enhance panel two.
  public static var burst: Int { 4 }
  /// Frame times jitter; a frame this close to the interval counts as due.
  static var slack: TimeInterval { 0.01 }

  private enum Screen { case none, read, unread }
  /// Whether the latest frame has been read.
  private var screen = Screen.none
  private var lastRead: TimeInterval?
  private var lastOutcome: Outcome?
  private var settled = false
  /// Fast reads since the reading last settled.
  private var fastReads = 0

  public init() {}

  /// When the held frame must be read, if one is held.
  public var deadline: TimeInterval? {
    guard screen == .unread else { return nil }
    return lastRead.map { $0 + Self.interval }
  }

  /// A new frame. Streamed video never repeats exactly, and pixels that only look the same can
  /// read differently, so a new frame is never answered from the last read.
  public mutating func frame(at time: TimeInterval) -> Decision {
    screen = .unread
    return readIfDue(at: time)
  }

  /// A frame that repeats the one before it, which may be held. `reusable` when the last read's
  /// outcome can be delivered again.
  public mutating func idle(at time: TimeInterval, reusable: Bool) -> Decision {
    switch screen {
    case .none: return .ignore
    case .read where reusable && isFresh(at: time): return .reuse
    case .read:
      screen = .unread
      return readIfDue(at: time)
    case .unread: return readIfDue(at: time)
    }
  }

  /// A timer at `deadline`, so a held frame is read on time even if no frame follows it.
  public mutating func tick(at time: TimeInterval) -> Decision {
    screen == .unread ? readIfDue(at: time) : .ignore
  }

  /// What a read or reuse delivered.
  public mutating func delivered(_ outcome: Outcome) {
    settled = lastOutcome == outcome
    lastOutcome = outcome
    if settled { fastReads = 0 }
  }

  /// Whether the last read is recent enough for its outcome to stand in for another.
  private func isFresh(at time: TimeInterval) -> Bool {
    lastRead.map { time - $0 < Self.refresh - Self.slack } ?? false
  }

  private mutating func readIfDue(at time: TimeInterval) -> Decision {
    if let lastRead, time - lastRead < Self.interval - Self.slack {
      if settled || fastReads >= Self.burst { return .hold }
      fastReads += 1
    }
    lastRead = time
    screen = .read
    return .read
  }
}
