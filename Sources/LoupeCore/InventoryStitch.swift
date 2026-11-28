import Foundation

/// The in-game Inventory list, read card by card in list order and put together a screen at a
/// time.
///
/// Nothing measures how far a scroll went. After each scroll, the app reads the first row that
/// shows whole, and `place` finds it among the rows already read by its cards; the rows below it
/// on screen follow on from there. A scroll that went past everything read finds no place, and
/// the app scrolls back. So a row can't be skipped or read twice without notice, and two
/// identical cards in different tiles stay two pieces.
public struct InventoryStitch: Sendable {
  /// What a tile's card turned out to be.
  public enum Card: Equatable, Sendable {
    case read(Artifact)
    /// A card of a rarity Loupe doesn't save, by its text and level.
    case other(key: String, level: Int)
    /// No card could be read for the tile.
    case unread

    /// What tells this card from another, whatever its roll rule. Nil when unread.
    public var key: String? {
      switch self {
      case .read(let artifact): artifact.cardKey
      case .other(let key, _): key
      case .unread: nil
      }
    }

    public var level: Int? {
      switch self {
      case .read(let artifact): artifact.level
      case .other(_, let level): level
      case .unread: nil
      }
    }
  }

  public enum Ending: Equatable, Sendable {
    /// Reached a piece below the minimum level.
    case belowMinimum
    case endOfList
    /// The scan couldn't tell where it was.
    case lostTrack(String)
    /// The app stopped it.
    case stopped

    /// Whether every piece at or above the minimum level was read.
    public var isComplete: Bool { self == .belowMinimum || self == .endOfList }
  }

  public let columns: Int
  public let minimumLevel: Int
  /// Every tile read, in list order: row by row, left to right.
  public private(set) var cards: [Card] = []
  public private(set) var ending: Ending?
  /// A vacant tile showed where the list ends.
  public private(set) var endSeen = false

  public init(columns: Int, minimumLevel: Int = 1) {
    precondition(columns > 0)
    self.columns = columns
    self.minimumLevel = minimumLevel
  }

  /// Rows read so far, the last one possibly short at the end of the list.
  public var rows: Int { (cards.count + columns - 1) / columns }

  /// The pieces read, in list order.
  public var artifacts: [Artifact] {
    cards.compactMap { if case .read(let artifact) = $0 { artifact } else { nil } }
  }

  /// Cards of rarities Loupe doesn't save.
  public var others: Int { cards.filter { if case .other = $0 { true } else { false } }.count }

  /// Tiles whose card couldn't be read.
  public var missed: Int { cards.filter { $0 == .unread }.count }

  /// Which row already read `row` is, the cards of a row read at the top of a screen: the row
  /// whose cards agree with it wherever both were read, with at least two agreeing, or all of
  /// a row of one, and a row as long. Of several, the one nearest `expected`. Nil when none
  /// is, as after a scroll past every row read.
  public func place(_ row: [Card], near expected: Int?) -> Int? {
    guard !row.isEmpty else { return nil }
    let candidates = (0..<rows).filter { index in
      let start = index * columns
      let known = Array(cards[start..<min(cards.count, start + columns)])
      guard known.count == row.count else { return false }
      var agreeing = 0
      for (a, b) in zip(known, row) {
        guard let a = a.key, let b = b.key else { continue }
        guard a == b else { return false }
        agreeing += 1
      }
      return agreeing >= min(2, row.count)
    }
    guard candidates.count > 1 else { return candidates.first }
    guard let expected else { return nil }
    let nearest = candidates.min { abs($0 - expected) < abs($1 - expected) }!
    // Two rows equally near can't be told apart.
    let tied = candidates.filter { abs($0 - expected) == abs(nearest - expected) }
    return tied.count == 1 ? nearest : nil
  }

  /// Adds the next tile's card, in list order. `label` is the level read under the tile, if
  /// any. A card below the minimum ends the scan there, unless the label read a level at or
  /// above it: then one of the two is misread, and the tile is left unread. Returns whether the
  /// scan goes on.
  @discardableResult public mutating func add(_ card: Card, label: Int? = nil) -> Bool {
    guard ending == nil else { return false }
    if let level = card.level, level < minimumLevel {
      guard let label, label >= minimumLevel else {
        ending = .belowMinimum
        return false
      }
      cards.append(.unread)
      return true
    }
    cards.append(card)
    return true
  }

  /// Ends the scan. `endSeen` when a vacant tile showed the end of the list.
  public mutating func finish(_ ending: Ending, endSeen: Bool = false) {
    guard self.ending == nil else { return }
    self.ending = ending
    self.endSeen = endSeen
  }

  /// The levels at which every piece was read, for telling which saved pieces are gone. Every
  /// level down to the minimum once the scan reached it, every level at a list seen to end,
  /// and otherwise only the levels above the lowest read, since the list is sorted by level. A
  /// tile that couldn't be read leaves out the levels it could have, those between the pieces
  /// either side of it, or any below the last when it's the last.
  public var coveredLevels: Set<Int> {
    guard let ending else { return [] }
    var covered: Set<Int>
    switch ending {
    case .endOfList where endSeen: covered = Set(0...20)
    case .belowMinimum: covered = Set(minimumLevel...20)
    default:
      guard let lowest = cards.compactMap(\.level).min(), lowest < 20 else { return [] }
      covered = Set((lowest + 1)...20)
    }
    for (index, card) in cards.enumerated() where card == .unread {
      let above = cards[..<index].last { $0.level != nil }?.level ?? 20
      let below = cards[(index + 1)...].first { $0.level != nil }?.level ?? 0
      covered.subtract(min(above, below)...max(above, below))
    }
    return covered
  }
}

/// What the scan does in the game, supplied by the app: look at the grid, click and read tiles,
/// turn the wheel, and wait.
@MainActor public protocol InventoryStitchGame: AnyObject {
  /// The grid as it shows now, once still. Nil when it can't be found.
  func screen() async throws -> InventoryStitch.Screen?
  /// Clicks each tile in turn and returns its card, in the same order.
  func read(_ tiles: [InventoryStitch.Tile]) async throws -> [InventoryStitch.Card]
  /// Turns the wheel `lines` lines, positive as `CGEvent` counts up, and returns whether the
  /// grid moved.
  func scroll(_ lines: Int) async throws -> Bool
  func pause(_ seconds: Double) async throws
  func log(_ line: String)
}

extension InventoryStitch {
  public struct Tile: Equatable, Sendable {
    /// Where to click, in window coordinates from the top left.
    public var point: CGPoint
    /// The level read under the tile, if any.
    public var label: Int?
    /// No tile here: the list has ended.
    public var vacant: Bool

    public init(point: CGPoint, label: Int? = nil, vacant: Bool = false) {
      self.point = point
      self.label = label
      self.vacant = vacant
    }
  }

  /// The rows the grid shows whole, top to bottom, each with a tile per column.
  public struct Screen: Equatable, Sendable {
    public var rows: [[Tile]]
    public init(rows: [[Tile]]) { self.rows = rows }
  }

  /// Reads the list from the top, which it must start at, down to the first piece below
  /// `minimumLevel` or the end. The error is why it stopped early, if it did.
  @MainActor public static func scan(
    _ game: some InventoryStitchGame, minimumLevel: Int = 1
  ) async -> (InventoryStitch, Error?) {
    var stitch: InventoryStitch?
    do {
      try await scan(game, minimumLevel: minimumLevel, into: &stitch)
      return (stitch ?? InventoryStitch(columns: 1, minimumLevel: minimumLevel), nil)
    } catch {
      var stopped = stitch ?? InventoryStitch(columns: 1, minimumLevel: minimumLevel)
      stopped.finish(.stopped)
      return (stopped, error)
    }
  }

  /// Lines a wheel turn of these takes to scroll a row, until a scroll shows how many.
  static let guessedLinesPerRow = 10.0

  @MainActor private static func scan(
    _ game: some InventoryStitchGame, minimumLevel: Int, into result: inout InventoryStitch?
  ) async throws {
    guard let first = try await game.screen(), let width = first.rows.first?.count, width > 0
    else {
      var empty = InventoryStitch(columns: 1, minimumLevel: minimumLevel)
      empty.finish(.lostTrack("Couldn't find the Inventory grid."))
      result = empty
      return
    }
    result = InventoryStitch(columns: width, minimumLevel: minimumLevel)

    // Which way is down, from the top: one way the list can't go, the other it can. Three
    // lines, so a still screen can't be mistaken for a move or the other way round.
    // Neither way moving may be the game slow to answer: look again after a wait.
    let probe = 3
    var down: Int?
    for wait in [0.0, 2.0, 4.0] where down == nil {
      if wait > 0 {
        game.log("the list didn't move either way; waiting \(Int(wait))s")
        try await game.pause(wait)
      }
      if try await game.scroll(probe) {
        _ = try await game.scroll(-probe)
        if try await game.scroll(-probe) {
          _ = try await game.scroll(probe)
          result!.finish(
            .lostTrack("The list wasn't at the top. Scroll it to the top, then scan."))
          return
        }
        down = probe.signum()
      } else if try await game.scroll(-probe) {
        _ = try await game.scroll(probe)
        down = -probe.signum()
      }
    }
    game.log("down is \(down.map(String.init) ?? "nowhere: the list doesn't scroll")")
    // Back to the top for sure: a turn back needn't undo a turn exactly, and at the top more
    // turns up do nothing.
    if let down { _ = try await game.scroll(-down * probe * 2) }

    // The first screen, read whole.
    guard var screen = try await game.screen(), !screen.rows.isEmpty else {
      result!.finish(.lostTrack("Couldn't find the Inventory grid."))
      return
    }
    for (index, row) in screen.rows.enumerated() {
      let outcome = try await read(
        row, fullRowBelow: hasFullRow(screen.rows[(index + 1)...]), of: game, into: &result)
      if outcome == .ended { return }
      if outcome == .notTheEnd {
        // What's left is for the next screen; the scroll goes by the rows that were rows.
        screen.rows = Array(screen.rows[..<index])
        break
      }
    }
    guard let down else {
      result!.finish(.endOfList, endSeen: false)
      return
    }

    var top = 0
    var linesPerRow = guessedLinesPerRow
    var idle = 0
    while result!.ending == nil {
      // Scroll so the screen's last rows come to the top, leaving rows already read on screen
      // to find the place by.
      let rows = max(1, screen.rows.count - 2)
      let lines = max(1, Int((Double(rows) * linesPerRow).rounded()))
      // Only turns that moved the list count toward where it should be.
      var moved = try await game.scroll(down * lines)
      var turned = moved ? lines : 0
      // A list that doesn't move may still be loading: wait, longer each time.
      for wait in [2.0, 4.0, 6.0] where !moved {
        game.log("didn't move; waiting \(Int(wait))s")
        try await game.pause(wait)
        moved = try await game.scroll(down * lines)
        if moved { turned += lines }
      }
      guard moved else {
        result!.finish(.endOfList)
        return
      }

      // Find the first row shown among the rows read; past them all, scroll back a scroll's
      // worth and look again. Any row read will do, so backing up too far does no harm.
      var placed: Int?
      var next = screen
      for attempt in 0..<6 {
        guard let shown = try await game.screen(), let firstRow = shown.rows.first else {
          result!.finish(.lostTrack("The Inventory grid is no longer on screen."))
          return
        }
        next = shown
        let expected = top + Int((Double(turned) / linesPerRow).rounded())
        placed = try await locate(firstRow, near: expected, in: result!, game: game)
        game.log(
          "first row shown is row \(placed.map(String.init) ?? "unknown"), expected \(expected)")
        if placed != nil { break }
        guard attempt < 5 else { break }
        _ = try await game.scroll(-down * lines)
        turned -= lines
      }
      guard let placed else {
        result!.finish(.lostTrack("Couldn't find its place in the list after scrolling."))
        return
      }
      if placed > top, turned > 0 {
        // Within reason of the last measure: a scroll the game took late can't throw it off.
        let measured = Double(turned) / Double(placed - top)
        linesPerRow = min(2 * linesPerRow, max(0.5 * linesPerRow, measured))
      }
      top = placed
      screen = next

      // The rows below it, those not read yet, in order.
      var added = false
      rows: for (offset, row) in screen.rows.enumerated() where top + offset >= result!.rows {
        guard top + offset == result!.rows else {
          result!.finish(.lostTrack("A row was skipped."))
          return
        }
        switch try await read(
          row, fullRowBelow: hasFullRow(screen.rows[(offset + 1)...]), of: game, into: &result)
        {
        case .ended: return
        case .added: added = true
        case .notTheEnd:
          screen.rows = Array(screen.rows[..<offset])
          break rows
        }
      }
      idle = added ? 0 : idle + 1
      if idle >= 4 {
        result!.finish(.lostTrack("Scrolling found no new rows."))
        return
      }
    }
  }

  /// Which row read `row` is, clicking as few of its tiles as settle it. Two first, then one at
  /// a time, checked against the rows within two of `expected`: it's settled when just one of
  /// those agrees, on two tiles or more, and none disagrees. Rows further off would have to
  /// share two identical pieces in the same places to pass for it. Otherwise the whole row is
  /// read and checked against every row read.
  @MainActor private static func locate(
    _ row: [Tile], near expected: Int, in stitch: InventoryStitch,
    game: some InventoryStitchGame
  ) async throws -> Int? {
    let tiles = row.filter { !$0.vacant }
    guard !tiles.isEmpty, stitch.rows > 0 else { return nil }
    let nearby = (max(0, expected - 2)...max(0, expected + 2)).filter { $0 < stitch.rows }
    var seen: [Card?] = Array(repeating: nil, count: tiles.count)
    // How many tiles row `index` agrees on; nil when it disagrees on one, or has none there.
    func agreeing(_ index: Int) -> Int? {
      var count = 0
      for (column, card) in seen.enumerated() {
        guard let key = card?.key else { continue }
        let position = index * stitch.columns + column
        // A tile where the row read has none can't be the same row.
        guard position < stitch.cards.count else { return nil }
        guard let known = stitch.cards[position].key else { continue }
        guard known == key else { return nil }
        count += 1
      }
      return count
    }
    var clicked = 0
    while clicked < tiles.count {
      let batch = min(clicked == 0 ? 2 : 1, tiles.count - clicked)
      let cards = try await game.read(Array(tiles[clicked..<(clicked + batch)]))
      for (offset, card) in cards.enumerated() { seen[clicked + offset] = card }
      clicked += batch
      let fits = nearby.filter { agreeing($0) != nil }
      if fits.count == 1, let only = fits.first, (agreeing(only) ?? 0) >= 2 { return only }
      if fits.isEmpty { break }
    }
    if clicked < tiles.count {
      let rest = try await game.read(Array(tiles[clicked...]))
      for (offset, card) in rest.enumerated() { seen[clicked + offset] = card }
    }
    return stitch.place(seen.map { $0 ?? .unread }, near: expected)
  }

  /// What came of reading a row.
  private enum RowOutcome {
    case added
    /// At a piece below the minimum, or at the end of the list.
    case ended
    /// Vacant tiles in a row that can't be the list's last, so nothing was added.
    case notTheEnd
  }

  private static func hasFullRow(_ rows: ArraySlice<[Tile]>) -> Bool {
    rows.contains { !$0.contains(where: \.vacant) }
  }

  /// Reads a row into the stitch: to a piece below the minimum, or to a vacant tile, the end of
  /// the list. `fullRowBelow` when the screen shows a row with no vacant tile under it.
  ///
  /// The list fills its last row from the left, and no full row follows it. A row with vacant
  /// tiles anywhere else, or with a full row below it, or none of whose other tiles has a card
  /// to read, isn't the end: something pale under the grid fell on the rows' spacing, or a tile
  /// was misjudged. That row is left for the next screen, unadded, rather than end the scan.
  @MainActor private static func read(
    _ row: [Tile], fullRowBelow: Bool, of game: some InventoryStitchGame,
    into result: inout InventoryStitch?
  ) async throws -> RowOutcome {
    let tiles = row.filter { !$0.vacant }
    let cards = try await game.read(tiles)
    let ends = tiles.count < row.count
    if ends {
      let filledFromLeft = row.drop { !$0.vacant }.allSatisfy(\.vacant)
      let cardsRead = cards.filter { $0 != .unread }.count
      guard filledFromLeft, !fullRowBelow, cardsRead > 0 else {
        game.log(
          "row \(result!.rows) has vacant tiles but isn't the end of the list (vacant "
            + "\(row.indices.filter { row[$0].vacant }), full row below \(fullRowBelow), "
            + "cards read \(cardsRead)); left for the next screen")
        return .notTheEnd
      }
    }
    for (tile, card) in zip(tiles, cards) {
      guard result!.add(card, label: tile.label) else { return .ended }
    }
    if ends {
      result!.finish(.endOfList, endSeen: true)
      return .ended
    }
    return .added
  }
}
