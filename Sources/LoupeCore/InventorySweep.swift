import Foundation

/// Steps through the Inventory grid one tile at a time, from the top, and keeps the card each
/// tile shows. The app carries out each step (a click or a scroll) and reports what it saw.
///
/// It first finds which way the scroll wheel moves the list and how far one line goes, then
/// scrolls to the top, so every tile has a fixed place: its row counted from the top and its
/// column. Two identical cards in different places are two pieces. Scrolling is measured from
/// the screen, not assumed, so the place of each row stays known.
///
/// It stops at the first card below `minimumLevel`, which assumes the list is sorted by level,
/// at the end of the list, or when it can no longer tell where it is. The list holds every
/// rarity; a card of one Loupe doesn't save is passed over, but still marks its place.
public struct InventorySweep: Sendable {
  public struct Cell: Hashable, Comparable, Sendable {
    /// Counted from the top of the list.
    public let row: Int
    public let column: Int
    public init(row: Int, column: Int) {
      self.row = row
      self.column = column
    }
    public static func < (a: Cell, b: Cell) -> Bool {
      (a.row, a.column) < (b.row, b.column)
    }
  }

  public enum Step: Equatable, Sendable {
    /// Click the tile at `point`, in window coordinates from the top left, and report its card.
    /// `level` is the level read under it, if any.
    case click(Cell, point: CGPoint, level: Int?)
    /// Turn the scroll wheel `lines` lines, positive as `CGEvent` counts up, then report the
    /// screen once it's still. `expected` is how far the content should move up, in window
    /// heights, when it's known.
    case scroll(lines: Int, expected: Double?)
    case finish(Ending)
  }

  public enum Ending: Equatable, Sendable {
    /// Reached a piece below the minimum level.
    case belowMinimum
    case endOfList
    /// Clicked tiles kept showing the same card.
    case clicksNotLanding
    /// The grid moved in a way the sweep couldn't follow.
    case lostTrack(String)
    /// The app stopped it.
    case stopped

    /// Whether every piece at or above the minimum level was read.
    public var isComplete: Bool { self == .belowMinimum || self == .endOfList }
  }

  public enum Card: Equatable, Sendable {
    case read(Artifact)
    /// A card of a rarity Loupe doesn't save, by its text and level.
    case other(key: String, level: Int)
    /// The card on screen is still the one from before the click: it didn't land.
    case unchanged
    /// No card could be read for the tile.
    case unread

    /// What tells this card from the next one, whatever its roll rule. Nil for no card.
    public var key: String? {
      switch self {
      case .read(let artifact): artifact.cardKey
      case .other(let key, _): key
      case .unchanged, .unread: nil
      }
    }

    /// What two readings of the same card share exactly. Nil for no card.
    public var signature: String? {
      switch self {
      case .read(let artifact): artifact.signature
      case .other(let key, _): key
      case .unchanged, .unread: nil
      }
    }

    public var level: Int? {
      switch self {
      case .read(let artifact): artifact.level
      case .other(_, let level): level
      case .unchanged, .unread: nil
      }
    }
  }

  public let minimumLevel: Int
  /// The card read at each place.
  public private(set) var pieces: [Cell: Artifact] = [:]
  /// The level of each card passed over for its rarity.
  public private(set) var others: [Cell: Int] = [:]
  /// Tiles clicked twice with no new card read.
  public private(set) var missed: Set<Cell> = []
  public private(set) var ending: Ending?

  private enum Phase {
    /// One line up, to learn which way is up and how far a line goes.
    case probeUp
    /// One line down, when a line up didn't move: at the top already, or the wheel is reversed.
    case probeDown
    /// Back up the line `probeDown` went down.
    case returnUp
    /// Whole screens up, until the list stops moving.
    case seekTop(bursts: Int)
    case reading
  }

  private struct Pending: Equatable {
    var cell: Cell
    var level: Int?
    /// A tile right of every read label in the screen's last row, not seen to be vacant: it may
    /// be past the end.
    var uncertain: Bool
    /// Put back once, behind the next tile, after it showed the card from before the click.
    var deferred = false
  }

  private var phase = Phase.probeUp
  /// The wheel direction that moves toward the top of the list.
  private var up = 1
  private var screen: InventoryGrid
  /// The first row's label with the list at the top.
  private var originY = 0.0
  /// How far the content has moved up since the top, in window heights.
  private var offset = 0.0
  private var lineDistance = 0.0
  private var measured = (distance: 0.0, lines: 0)
  private var queue: [Pending] = []
  private var current: (pending: Pending, retried: Bool)?
  /// The last card read, of whatever rarity.
  private var previous: String?
  private var repeats = 0
  /// Tiles past the end of the list, seen to be vacant.
  private var empty: Set<Cell> = []
  private var reachedEnd = false
  /// Neither way of the wheel moved the list.
  private var wheelDead = false
  /// Scrolls since the last tile clicked.
  private var idleScrolls = 0
  private static let maximumSeekBursts = 200

  public init(minimumLevel: Int = 1, screen: InventoryGrid) {
    self.minimumLevel = minimumLevel
    self.screen = screen
  }

  /// The levels at which every piece was read, for telling which saved pieces are gone. Every
  /// level down to the minimum once the sweep is complete, every level after reaching the end,
  /// and only the levels above the lowest read when it stopped early, since the list is sorted
  /// by level. A tile that couldn't be read leaves out the levels it could have, those between
  /// the pieces either side of it, or any below the last when it's the last.
  ///
  /// A wheel that never moved the list covers nothing, since the sweep can't tell it started at
  /// the top. The end of the list covers every level only where it's seen to end, at a vacant
  /// tile in the last row; otherwise a last row whose labels were all missed could hide more.
  public var coveredLevels: Set<Int> {
    guard let ending, !wheelDead else { return [] }
    let read = levels.sorted { $0.key < $1.key }
    let lastRow = (read.map(\.key.row) + missed.map(\.row)).max() ?? 0
    let endsVisibly = empty.contains { $0.row >= lastRow }
    var covered: Set<Int>
    switch ending {
    case .endOfList where endsVisibly: covered = Set(0...20)
    case .belowMinimum: covered = Set(minimumLevel...20)
    default:
      guard let lowest = read.map(\.value).min(), lowest < 20 else { return [] }
      covered = Set((lowest + 1)...20)
    }
    for cell in missed {
      let above = read.last { $0.key < cell }?.value ?? 20
      let below = read.first { cell < $0.key }?.value ?? 0
      covered.subtract(min(above, below)...max(above, below))
    }
    return covered
  }

  /// The level of every card read, of whatever rarity, by place.
  private var levels: [Cell: Int] {
    pieces.mapValues(\.level).merging(others) { a, _ in a }
  }

  /// The pieces in list order.
  public var artifacts: [Artifact] { pieces.sorted { $0.key < $1.key }.map(\.value) }

  /// The first step.
  public mutating func start() -> Step {
    phase = .probeUp
    return .scroll(lines: up, expected: nil)
  }

  /// Stops where it is.
  public mutating func stop() -> Step { finish(.stopped) }

  /// After a scroll: the screen it left, or nil if the grid couldn't be read, and how far the
  /// content moved up, in window heights, as measured from the pictures. Nil when that couldn't
  /// be measured.
  public mutating func scrolled(to grid: InventoryGrid?, moved coarse: Double?) -> Step {
    guard ending == nil else { return .finish(ending!) }
    guard let grid else { return finish(.lostTrack("The Inventory grid is no longer on screen.")) }
    let pitch = screen.rowPitch
    let moved = coarse.map { Self.refine($0, before: screen, after: grid) }
    screen = grid
    let still = moved.map { abs($0) < 0.1 * pitch } ?? false
    switch phase {
    case .probeUp, .probeDown:
      guard let moved else { return finish(.lostTrack("Couldn't measure a scroll.")) }
      let probedDown = phaseIsProbeDown
      if still {
        if probedDown {
          // Neither way moves: the list fits on one screen, or the wheel doesn't reach it.
          reachedEnd = true
          wheelDead = true
          return beginReading()
        }
        phase = .probeDown
        return .scroll(lines: -up, expected: nil)
      }
      lineDistance = abs(moved)
      measured = (abs(moved), 1)
      // Moving toward the top moves the content down, which is a negative move.
      let towardTop = moved < 0
      if probedDown && !towardTop {
        // Down went down, and up didn't move: it was at the top. Go back up the line.
        phase = .returnUp
        return .scroll(lines: up, expected: -lineDistance)
      }
      // Up went down, or down went up: the wheel is the other way round.
      if towardTop == probedDown { up = -up }
      return seekTop(bursts: 0)
    case .returnUp:
      // Unless the line back up is seen, the list may not be at the top.
      guard let moved, moved < -0.5 * lineDistance else {
        return finish(.lostTrack("Couldn't confirm the return to the top of the list."))
      }
      return beginReading()
    case .seekTop(let bursts):
      if still { return beginReading() }
      guard bursts < Self.maximumSeekBursts else {
        return finish(.lostTrack("Couldn't find the top of the list."))
      }
      return seekTop(bursts: bursts + 1)
    case .reading:
      guard let moved else { return finish(.lostTrack("Couldn't measure a scroll.")) }
      let expected = Double(lastLines) * lineDistance
      if (lastLines > 0 && moved <= -0.1 * pitch) || (lastLines < 0 && moved >= 0.1 * pitch) {
        return finish(.lostTrack("The list moved the wrong way."))
      }
      if lastLines > 0 && moved < 0.1 * pitch {
        // Asked to go down and didn't move: the list has ended.
        reachedEnd = true
      } else if abs(moved - expected) < 0.3 * abs(expected) {
        // A short move at the end of the list says nothing about a line.
        measured.distance += abs(moved)
        measured.lines += abs(lastLines)
        lineDistance = measured.distance / Double(measured.lines)
      }
      offset += moved
      idleScrolls += 1
      return plan()
    }
  }

  /// After a click: the card the tile showed.
  public mutating func clicked(_ card: Card) -> Step {
    guard ending == nil else { return .finish(ending!) }
    guard let (pending, retried) = current else { return plan() }
    switch card {
    case .unread:
      if !retried { return click(pending, retried: true) }
      missed.insert(pending.cell)
    case .read(let artifact) where previous != artifact.cardKey:
      if artifact.level < minimumLevel {
        if let step = belowMinimum(pending, key: artifact.cardKey) { return step }
        break
      }
      repeats = 0
      pieces[pending.cell] = artifact
      previous = artifact.cardKey
    case .other(let key, let level) where previous != key:
      if level < minimumLevel {
        if let step = belowMinimum(pending, key: key) { return step }
        break
      }
      repeats = 0
      others[pending.cell] = level
      previous = key
    case .read, .other, .unchanged:
      // The card is still the one from before the click: the click didn't land, the tile was
      // already selected, or it's an identical copy of the last. Click once more, then come
      // back to it after the next tile, once a different card is up. A tile that still shows
      // the old card then is left for the user.
      if !retried { return click(pending, retried: true) }
      repeats += 1
      if repeats >= 3 { return finish(.clicksNotLanding) }
      if !pending.deferred && !queue.isEmpty {
        var later = pending
        later.deferred = true
        queue.insert(later, at: 1)
      } else {
        missed.insert(pending.cell)
      }
    }
    current = nil
    return next()
  }

  /// A card below the minimum ends the sweep, unless the label under its tile read a level at
  /// or above it: then one of the two is misread, and ending there would take every level as
  /// covered with tiles still unread. Such a tile is left unread, since clicking it again would
  /// show the same card, and the sweep goes on: nil.
  private mutating func belowMinimum(_ pending: Pending, key: String) -> Step? {
    guard let label = pending.level, label >= minimumLevel else { return finish(.belowMinimum) }
    missed.insert(pending.cell)
    previous = key
    repeats = 0
    return nil
  }

  private var phaseIsProbeDown: Bool {
    if case .probeDown = phase { return true }
    return false
  }

  /// The lines of the last scroll while reading, counting down as positive.
  private var lastLines = 0

  private mutating func seekTop(bursts: Int) -> Step {
    phase = .seekTop(bursts: bursts)
    let lines = max(1, Int(0.6 * viewHeight / max(lineDistance, 1e-6)))
    return .scroll(lines: up * lines, expected: nil)
  }

  /// The height of the rows on screen, about what one screen scrolls.
  private var viewHeight: Double {
    guard let first = screen.rows.first, let last = screen.rows.last else { return 0 }
    return last.y - first.y + screen.rowPitch
  }

  private mutating func beginReading() -> Step {
    phase = .reading
    offset = 0
    originY = screen.rows.first?.y ?? 0
    return plan()
  }

  /// Queues the unread tiles on screen, or scrolls to the next unread row.
  private mutating func plan() -> Step {
    queue = []
    let pitch = screen.rowPitch
    let lastRow = screen.rows.indices.last
    for (index, row) in screen.rows.enumerated() {
      // A row scrolled partly out of view at the top can't be clicked.
      guard row.y >= originY - 0.3 * pitch else { continue }
      let place = Int(((row.y + offset - originY) / pitch).rounded())
      guard place >= 0 else { continue }
      let lastRead = row.levels.lastIndex { $0 != nil } ?? -1
      for column in screen.columns.indices {
        let cell = Cell(row: place, column: column)
        let level = row.levels[column]
        // Only the last row on screen can end early; elsewhere a missing strip is a misreading.
        // What this screen shows replaces what an earlier one did.
        if index == lastRow && level == nil && row.vacant[column] {
          empty.insert(cell)
        } else {
          empty.remove(cell)
        }
        guard pieces[cell] == nil, others[cell] == nil, !missed.contains(cell),
          !(empty.contains(cell) && level == nil)
        else { continue }
        queue.append(
          Pending(cell: cell, level: level, uncertain: index == lastRow && column > lastRead))
      }
    }
    return next()
  }

  private mutating func next() -> Step {
    if !queue.isEmpty {
      idleScrolls = 0
      return click(queue.removeFirst(), retried: false)
    }
    if reachedEnd {
      // A list that never scrolled may be the first screen of many, unless it visibly ends.
      if wheelDead && empty.isEmpty {
        return finish(.lostTrack("The list didn't scroll, so only the first screen was read."))
      }
      return finish(.endOfList)
    }
    guard idleScrolls < 4 else { return finish(.lostTrack("Scrolling found no new tiles.")) }
    // Bring the row after the last one handled near the top, scrolling at most half a screen
    // so enough stays on screen to measure the move.
    let pitch = screen.rowPitch
    // Vacant tiles don't count: one seen in error mustn't skip a row.
    let done = pieces.keys.map(\.row) + others.keys.map(\.row) + missed.map(\.row)
    let nextRow = (done.max() ?? -1) + 1
    let target = originY + 0.25 * pitch
    let now = originY + Double(nextRow) * pitch - offset
    let distance = min(now - target, max(pitch, 0.5 * viewHeight))
    let lines = Int((distance / max(lineDistance, 1e-6)).rounded())
    lastLines = lines == 0 ? 1 : lines
    return .scroll(lines: -up * lastLines, expected: Double(lastLines) * lineDistance)
  }

  private mutating func click(_ pending: Pending, retried: Bool) -> Step {
    current = (pending, retried)
    let pitch = screen.rowPitch
    let y = originY + Double(pending.cell.row) * pitch - offset
    let x = screen.columns[pending.cell.column]
    return .click(pending.cell, point: CGPoint(x: x, y: y - 0.35 * pitch), level: pending.level)
  }

  private mutating func finish(_ ending: Ending) -> Step {
    self.ending = ending
    // A tile put back to try again, or being tried, was never read.
    missed.formUnion(queue.filter(\.deferred).map(\.cell))
    if let current, current.retried || current.pending.deferred {
      missed.insert(current.pending.cell)
    }
    queue = []
    current = nil
    return .finish(ending)
  }

  /// The move from `before` to `after`, nearest `coarse`, that lines up their rows. A coarse
  /// measurement within half a row is enough; the rows' labels give the rest.
  static func refine(_ coarse: Double, before: InventoryGrid, after: InventoryGrid) -> Double {
    let pitch = before.rowPitch
    guard pitch > 0, let a = phase(before.rows.map(\.y), pitch: pitch),
      let b = phase(after.rows.map(\.y), pitch: pitch)
    else { return coarse }
    // The content moved up by s, so each row's y went down by s.
    let remainder = (a - b).truncatingRemainder(dividingBy: pitch)
    let turns = ((coarse - remainder) / pitch).rounded()
    return remainder + turns * pitch
  }

  /// Where rows fall within a pitch, averaged around the circle.
  private static func phase(_ ys: [Double], pitch: Double) -> Double? {
    guard !ys.isEmpty else { return nil }
    let angles = ys.map { 2 * Double.pi * $0 / pitch }
    let x = angles.map(cos).reduce(0, +)
    let y = angles.map(sin).reduce(0, +)
    guard x * x + y * y > 1e-12 else { return nil }
    var angle = atan2(y, x)
    if angle < 0 { angle += 2 * .pi }
    return angle / (2 * .pi) * pitch
  }
}
