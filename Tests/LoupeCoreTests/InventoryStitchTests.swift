import Foundation
import LoupeCore
import Testing

/// A flower whose CRIT Rate rolled at every upgrade. Set names are letters only, since the set
/// key drops everything else.
private func piece(_ index: Int, level: Int) throws -> Artifact {
  var name = ""
  var value = index
  repeat {
    name.append(Character(UnicodeScalar(UInt8(97 + value % 26))))
    value /= 26
  } while value > 0
  let rolls = 1 + level / 4
  return try Artifact(
    setName: "Set " + name, slot: .flower, main: .hp, level: level,
    substats: [
      Substat(.critRate, (3.89 * Double(rolls) * 10).rounded() / 10), Substat(.atk, 19.5),
      Substat(.def, 23.2), Substat(.hpPercent, 5.8),
    ])
}

/// The Inventory list as the scan sees it: eight tiles a row, five and a fifth rows on screen,
/// a wheel that scrolls a fraction of a row a line.
@MainActor private final class Game: InventoryStitchGame {
  static let columns = 8
  static let visible = 5.2

  var pieces: [Artifact]
  /// The first row on screen, in rows from the top, fractional mid-scroll.
  var position: Double
  var rowsPerLine = 0.098
  /// The wheel's lines go the other way.
  var reversed = false
  /// Scrolls down, counted from 1, that don't move the list, as while the game loads more.
  var stalls: Set<Int> = []
  /// Scrolls down, counted from 1, that go three times as far.
  var overshoots: Set<Int> = []
  /// Pieces read as one to three stars, and pieces whose card can't be read.
  var lowRarity: Set<Int> = []
  var unreadable: Set<Int> = []
  /// Labels read wrong, by piece.
  var labels: [Int: Int] = [:]
  /// Under the last row shown, a row of tiles that aren't: the pale buttons in the bar under
  /// the grid, falling on the rows' spacing. The first five pass for tiles and the rest for
  /// vacant, and a click on one brings up no card.
  var ghostRow = false
  /// Pieces whose tile is judged vacant the first time a screen shows it.
  var falseVacant: Set<Int> = []
  private(set) var ghostClicks = 0
  /// Scales each scroll down, from 1 up, to vary how far the wheel goes.
  var jitter: ((Int) -> Double)?
  private(set) var scrollsDown = 0
  private(set) var pauses = 0
  private(set) var reads: [Int] = []
  private(set) var lines: [String] = []

  init(_ pieces: [Artifact], position: Double = 0) {
    self.pieces = pieces
    self.position = position
  }

  var rowCount: Int { (pieces.count + Self.columns - 1) / Self.columns }
  var bottom: Double { max(0, Double(rowCount) - Self.visible) }

  func screen() async throws -> InventoryStitch.Screen? {
    let first = Int(position.rounded(.up))
    let rows = (first..<rowCount).filter { Double($0 + 1) <= position + Self.visible + 1e-9 }
    let misjudged = falseVacant
    falseVacant.subtract(rows.flatMap { row in (0..<Self.columns).map { row * Self.columns + $0 } })
    var shown = rows.map { row in
      (0..<Self.columns).map { column in
        let index = row * Self.columns + column
        let present = index < pieces.count
        return InventoryStitch.Tile(
          point: CGPoint(x: Double(column), y: Double(row)),
          label: present ? labels[index] ?? pieces[index].level : nil,
          vacant: !present || misjudged.contains(index))
      }
    }
    if ghostRow {
      shown.append(
        (0..<Self.columns).map { column in
          InventoryStitch.Tile(point: CGPoint(x: Double(column), y: -1), vacant: column >= 5)
        })
    }
    return InventoryStitch.Screen(rows: shown)
  }

  func read(_ tiles: [InventoryStitch.Tile]) async throws -> [InventoryStitch.Card] {
    tiles.map { tile in
      if tile.point.y < 0 {
        ghostClicks += 1
        return .unread
      }
      // A click only lands on a tile on screen.
      let row = Int(tile.point.y)
      precondition(
        Double(row) >= position - 1e-9 && Double(row + 1) <= position + Self.visible + 1e-9)
      let index = row * Self.columns + Int(tile.point.x)
      reads.append(index)
      if unreadable.contains(index) { return .unread }
      let piece = pieces[index]
      if lowRarity.contains(index) {
        return .other(key: "low " + piece.cardKey, level: piece.level)
      }
      return .read(piece)
    }
  }

  func scroll(_ lines: Int) async throws -> Bool {
    let down = reversed ? lines > 0 : lines < 0
    var move = Double(abs(lines)) * rowsPerLine * (down ? 1 : -1)
    if down {
      scrollsDown += 1
      if stalls.contains(scrollsDown) { return false }
      if overshoots.contains(scrollsDown) { move *= 3 }
      if let jitter { move *= jitter(scrollsDown) }
    }
    let before = position
    position = min(bottom, max(0, position + move))
    return abs(position - before) > 1e-9
  }

  func pause(_ seconds: Double) async throws { pauses += 1 }
  func log(_ line: String) { lines.append(line) }
}

@MainActor private func scan(_ game: Game) async -> InventoryStitch {
  let (stitch, error) = await InventoryStitch.scan(game)
  #expect(error == nil)
  return stitch
}

@MainActor @Test func aScanReadsEveryLevelledPieceOnceAndStopsAtTheFirstPlusZero() async throws {
  let pieces =
    try (0..<30).map { try piece($0, level: 20) } + (30..<71).map { try piece($0, level: 16) }
    + (71..<140).map { try piece($0, level: 0) }
  for rowsPerLine in [0.07, 0.098, 0.13] {
    let game = Game(pieces)
    game.rowsPerLine = rowsPerLine
    let stitch = await scan(game)
    #expect(stitch.ending == .belowMinimum)
    #expect(stitch.artifacts == Array(pieces.prefix(71)))
    #expect(stitch.coveredLevels == Set(1...20))
    // Each screen after the first clicks three tiles it read before to find its place; the
    // first +0 is clicked but not kept.
    let screens = game.lines.filter { $0.hasPrefix("first row shown") }.count
    #expect(game.reads.count - stitch.cards.count == 3 * screens + 1)
  }
}

@MainActor @Test func identicalCardsInDifferentTilesAreSeparatePieces() async throws {
  var pieces = try (0..<60).map { try piece($0, level: 20) }
  let copy = try piece(3, level: 20)
  // Beside each other, far apart, and a whole row of them, twice over.
  for index in [4, 5, 30] + Array(40..<48) + Array(48..<56) { pieces[index] = copy }
  pieces += try (60..<80).map { try piece($0, level: 0) }
  let game = Game(pieces)
  let stitch = await scan(game)
  #expect(stitch.ending == .belowMinimum)
  #expect(stitch.artifacts == Array(pieces.prefix(60)))
}

@MainActor @Test func aScrollTheGameIgnoresIsWaitedOut() async throws {
  let pieces =
    try (0..<100).map { try piece($0, level: 20) } + (100..<120).map { try piece($0, level: 0) }
  let game = Game(pieces)
  game.stalls = [2, 3, 6]
  let stitch = await scan(game)
  #expect(stitch.ending == .belowMinimum)
  #expect(stitch.artifacts == Array(pieces.prefix(100)))
  #expect(game.pauses == 3)
}

@MainActor @Test func aScrollThatGoesTooFarIsTakenBack() async throws {
  let pieces =
    try (0..<120).map { try piece($0, level: 20) } + (120..<140).map { try piece($0, level: 0) }
  let game = Game(pieces)
  game.overshoots = [2, 4]
  let stitch = await scan(game)
  #expect(stitch.ending == .belowMinimum)
  #expect(stitch.artifacts == Array(pieces.prefix(120)))
  #expect(game.lines.contains { $0.contains("unknown") })
}

@MainActor @Test func aListNotAtTheTopIsntScanned() async throws {
  let pieces = try (0..<100).map { try piece($0, level: 20) }
  let game = Game(pieces, position: 3.4)
  let stitch = await scan(game)
  guard case .lostTrack(let reason) = stitch.ending else {
    Issue.record("Expected to stop, got \(String(describing: stitch.ending))")
    return
  }
  #expect(reason.contains("top"))
  #expect(stitch.cards.isEmpty)
  #expect(abs(game.position - 3.4) < 1e-9)
}

@MainActor @Test func aReversedWheelIsLearnedAtTheTop() async throws {
  let pieces =
    try (0..<70).map { try piece($0, level: 12) } + (70..<90).map { try piece($0, level: 0) }
  let game = Game(pieces)
  game.reversed = true
  let stitch = await scan(game)
  #expect(stitch.ending == .belowMinimum)
  #expect(stitch.artifacts == Array(pieces.prefix(70)))
}

@MainActor @Test func aListThatFitsOnOneScreenEndsWhereItsSeenToEnd() async throws {
  let pieces = try (0..<21).map { try piece($0, level: 8) }
  let stitch = await scan(Game(pieces))
  #expect(stitch.ending == .endOfList)
  #expect(stitch.endSeen)
  #expect(stitch.artifacts == pieces)
  #expect(stitch.coveredLevels == Set(0...20))
}

@MainActor @Test func aLongListEndsAtItsLastTile() async throws {
  let ragged = try (0..<75).map { try piece($0, level: 20) }
  let stitch = await scan(Game(ragged))
  #expect(stitch.ending == .endOfList)
  #expect(stitch.endSeen)
  #expect(stitch.artifacts == ragged)
  // A last row that's full shows no vacant tile: the end is where scrolling stops.
  let full = try (0..<80).map { try piece($0, level: 20) }
  let game = Game(full)
  let fullStitch = await scan(game)
  #expect(fullStitch.ending == .endOfList)
  #expect(!fullStitch.endSeen)
  #expect(fullStitch.artifacts == full)
  #expect(game.pauses == 3)
  #expect(fullStitch.coveredLevels.isEmpty)
}

@MainActor @Test func lowRaritiesAndUnreadCardsKeepTheirPlace() async throws {
  let pieces =
    try (0..<20).map { try piece($0, level: 20) } + (20..<40).map { try piece($0, level: 12) }
    + (40..<60).map { try piece($0, level: 0) }
  let game = Game(pieces)
  game.lowRarity = [21, 33]
  game.unreadable = [25]
  let stitch = await scan(game)
  #expect(stitch.ending == .belowMinimum)
  #expect(stitch.others == 2)
  #expect(stitch.missed == 1)
  #expect(stitch.cards.count == 40)
  #expect(stitch.artifacts.count == 37)
  // The unread +12 leaves +12 out; the rest down to +1 are covered.
  #expect(stitch.coveredLevels == Set(1...20).subtracting([12]))
}

@MainActor @Test func aPlusZeroCardUnderAHigherLabelDoesntEndTheScan() async throws {
  let pieces =
    try (0..<20).map { try piece($0, level: 20) } + (20..<30).map { try piece($0, level: 8) }
    + (30..<50).map { try piece($0, level: 0) }
  var misread = pieces
  // The card of tile 24 reads +0, but its label +8.
  misread[24] = try piece(24, level: 0)
  let game = Game(misread)
  game.labels = [24: 8]
  let stitch = await scan(game)
  #expect(stitch.ending == .belowMinimum)
  #expect(stitch.cards.count == 30)
  #expect(stitch.cards[24] == .unread)
}

@MainActor @Test func aScanNeverSkipsOrRepeatsARowHoweverTheWheelGoes() async throws {
  var seed: UInt64 = 11
  func random() -> Double {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Double(seed >> 11) / Double(1 << 53)
  }
  var copies = try (0..<150).map { try piece($0, level: 20 - $0 / 10) }
  // Identical copies here and there, a whole row of them among them.
  for index in [7, 8, 50, 51, 52] + Array(80..<88) { copies[index] = copies[6] }
  let pieces = try copies + (150..<170).map { try piece($0, level: 0) }
  var finished = 0
  for _ in 0..<40 {
    let game = Game(pieces)
    game.rowsPerLine = 0.06 + 0.08 * random()
    // Stalls a game gets over within the scan's waits: never four turns in a row.
    var stalls: [Int] = []
    for turn in 1...30 where random() < 0.15 {
      if !(stalls.suffix(3) == [turn - 3, turn - 2, turn - 1]) { stalls.append(turn) }
    }
    let overshoots = (1...30).filter { _ in random() < 0.1 }
    game.stalls = Set(stalls)
    game.overshoots = Set(overshoots)
    let scales = (0..<200).map { _ in 0.7 + 0.6 * random() }
    game.jitter = { scales[$0 % scales.count] }
    let stitch = await scan(game)
    // Whatever happens, what it read is the list from the top, in order.
    #expect(stitch.artifacts == Array(pieces.prefix(stitch.artifacts.count)))
    if stitch.ending == .belowMinimum {
      finished += 1
      #expect(stitch.artifacts.count == 150)
    }
  }
  #expect(finished >= 36)
}

@MainActor @Test func paleButtonsUnderTheGridDontEndTheList() async throws {
  // As in a scan that stopped among the +16 pieces: what passes for a row under the grid, with
  // tiles that bring up no card and tiles that look vacant.
  let pieces =
    try (0..<40).map { try piece($0, level: 20) } + (40..<130).map { try piece($0, level: 16) }
    + (130..<150).map { try piece($0, level: 0) }
  let game = Game(pieces)
  game.ghostRow = true
  let stitch = await scan(game)
  #expect(stitch.ending == .belowMinimum)
  #expect(stitch.artifacts == Array(pieces.prefix(130)))
  #expect(stitch.missed == 0)
  #expect(stitch.coveredLevels == Set(1...20))
  #expect(game.ghostClicks > 0)
  #expect(game.lines.contains { $0.contains("isn't the end of the list") })

  // The list's real end still ends it, with the same row under it.
  let ragged = try (0..<75).map { try piece($0, level: 20) }
  let end = Game(ragged)
  end.ghostRow = true
  let ended = await scan(end)
  #expect(ended.ending == .endOfList)
  #expect(ended.endSeen)
  #expect(ended.artifacts == ragged)
}

@MainActor @Test func tilesMisjudgedVacantMidListDontEndIt() async throws {
  let pieces =
    try (0..<100).map { try piece($0, level: 20) } + (100..<120).map { try piece($0, level: 0) }
  // The last two of a row with full rows under it, the middle of another, the last three of a
  // row first read on the second screen, with full rows under it, and the last two of the
  // lowest row on that screen, with none under it.
  for misjudged: Set<Int> in [[22, 23], [12], [45, 46, 47], [62, 63]] {
    let game = Game(pieces)
    game.falseVacant = misjudged
    let stitch = await scan(game)
    #expect(stitch.ending == .belowMinimum)
    #expect(stitch.artifacts == Array(pieces.prefix(100)))
    #expect(stitch.missed == 0)
  }
}

@MainActor @Test func aRowLikeAnotherInTwoPlacesIsntTakenForIt() async throws {
  // A scroll that goes too far shows row 5 first, whose first two pieces are copies of row
  // 3's, near where row 3 should be.
  var pieces = try (0..<75).map { try piece($0, level: 20) }
  pieces[40] = pieces[24]
  pieces[41] = pieces[25]
  let game = Game(pieces)
  game.overshoots = [2]
  let stitch = await scan(game)
  #expect(stitch.ending == .endOfList)
  #expect(stitch.endSeen)
  #expect(stitch.artifacts == pieces)
}

@MainActor @Test func aWheelFasterThanGuessedStillGetsThere() async throws {
  // Twice the rows a line it guesses: every first scroll goes past the rows read.
  let pieces =
    try (0..<120).map { try piece($0, level: 20) } + (120..<140).map { try piece($0, level: 0) }
  let game = Game(pieces)
  game.rowsPerLine = 0.2
  let stitch = await scan(game)
  #expect(stitch.ending == .belowMinimum)
  #expect(stitch.artifacts == Array(pieces.prefix(120)))
}

@MainActor @Test func aRowWhoseTilesBringUpNoCardIsntTheEnd() async throws {
  // A last row whose cards weren't read can't show the list ends there: the scan stops where
  // scrolling does, without claiming it saw the end.
  let pieces = try (0..<21).map { try piece($0, level: 8) }
  let game = Game(pieces)
  game.unreadable = Set(16..<21)
  let stitch = await scan(game)
  #expect(stitch.ending == .endOfList)
  #expect(!stitch.endSeen)
  #expect(stitch.artifacts == Array(pieces.prefix(16)))
}

@Test func aRowIsPlacedByItsCards() throws {
  var stitch = InventoryStitch(columns: 4)
  let a = try (0..<4).map { InventoryStitch.Card.read(try piece($0, level: 20)) }
  let b = try (4..<8).map { InventoryStitch.Card.read(try piece($0, level: 20)) }
  for card in a + b + a { stitch.add(card) }
  #expect(stitch.place(b, near: nil) == 1)
  // Two rows alike: the one nearer where the scroll should have gone.
  #expect(stitch.place(a, near: nil) == nil)
  #expect(stitch.place(a, near: 2) == 2)
  #expect(stitch.place(a, near: 0) == 0)
  // An unread card matches anything, but two must agree.
  #expect(stitch.place([.unread, b[1], b[2], .unread], near: nil) == 1)
  #expect(stitch.place([.unread, .unread, .unread, b[3]], near: nil) == nil)
  // A row past everything read isn't anywhere.
  let c = try (8..<12).map { InventoryStitch.Card.read(try piece($0, level: 20)) }
  #expect(stitch.place(c, near: 3) == nil)
}
