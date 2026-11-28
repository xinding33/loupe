import Foundation
import LoupeCore
import Testing

/// A flower whose CRIT Rate rolled at every upgrade. Set names are letters only, since the set
/// key drops everything else.
private func piece(_ index: Int, level: Int, rarity: Int = 5) throws -> Artifact {
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

private func label(_ text: String, x: Double, y: Double) -> GridLabel {
  GridLabel(text: text, bounds: CGRect(x: x - 0.01, y: y - 0.0065, width: 0.02, height: 0.013))
}

@Test func levelLabelsReadTheWaysVisionReadsThem() {
  #expect(label("+20", x: 0, y: 0).level == 20)
  #expect(label("20", x: 0, y: 0).level == 20)
  #expect(label("-20", x: 0, y: 0).level == 20)
  #expect(label("+ 4", x: 0, y: 0).level == 4)
  #expect(label("+21", x: 0, y: 0).level == nil)
  #expect(label("2668/2700", x: 0, y: 0).level == nil)
  #expect(label("Salvage", x: 0, y: 0).level == nil)
}

@Test func theGridIsALatticeThroughTheLabelsItRead() throws {
  // Five rows of eight, as on a 2560-wide window, with a few labels missed.
  var labels: [GridLabel] = []
  for row in 0..<5 {
    for column in 0..<8 where (row * 8 + column) % 7 != 3 {
      labels.append(
        label(
          row == 2 && column == 4 ? "20" : "+20", x: 0.093 + Double(column) * 0.0765,
          y: 0.293 + Double(row) * 0.140))
    }
  }
  // A whole row missed: still placed between the rows around it.
  labels.removeAll { abs($0.bounds.midY - (0.293 + 3 * 0.140)) < 0.01 }
  labels.append(label("Lock Assistance", x: 0.17, y: 0.95))
  let grid = try #require(InventoryGrid.detect(labels))
  #expect(grid.columns.count == 8)
  #expect(grid.rows.count == 5)
  #expect(abs(grid.rowPitch - 0.140) < 0.001)
  #expect(abs(grid.columnPitch - 0.0765) < 0.001)
  #expect(grid.rows[3].levels.allSatisfy { $0 == nil })
  #expect(grid.rows[2].levels[4] == 20)
  #expect(grid.rows[0].levels[3] == nil)
  let tile = grid.tile(row: 1, column: 2)
  #expect(abs(tile.x - (0.093 + 2 * 0.0765)) < 0.001)
  #expect(abs(tile.y - (0.433 - 0.049)) < 0.001)

  // A later screen keeps the earlier lattice: a label left of it, or rows read only every
  // other row, can't renumber the columns or double the spacing.
  let later = [
    label("+20", x: 0.093 - 0.0765, y: 0.3), label("+20", x: 0.093, y: 0.3),
    label("+20", x: 0.093, y: 0.3 + 2 * 0.140),
  ]
  let kept = try #require(InventoryGrid.detect(later, known: grid))
  #expect(kept.columns == grid.columns)
  #expect(kept.rowPitch == grid.rowPitch)
  #expect(kept.rows.count == 3)

  // One row, placed with the pitch of an earlier screen.
  let single = [label("+16", x: 0.093, y: 0.5), label("+16", x: 0.093 + 0.0765, y: 0.5)]
  #expect(InventoryGrid.detect(single) == nil)
  let placed = try #require(InventoryGrid.detect(single, known: grid))
  #expect(placed.columns.count == 8)
  #expect(placed.rows.count == 1)
  #expect(placed.rows[0].levels[1] == 16)
}

@Test func aScrollIsMeasuredFromThePictures() {
  var seed: UInt64 = 7
  func noise() -> UInt8 {
    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return UInt8(truncatingIfNeeded: seed >> 33)
  }
  let width = 40
  let tall = (0..<(width * 300)).map { _ in noise() }
  func window(at top: Int) -> GrayImage {
    GrayImage(
      width: width, height: 100, pixels: Array(tall[(top * width)..<((top + 100) * width)]))
  }
  #expect(GrayImage.verticalShift(from: window(at: 50), to: window(at: 73), within: -90...90) == 23)
  #expect(
    GrayImage.verticalShift(from: window(at: 50), to: window(at: 31), within: -90...90) == -19)
  #expect(GrayImage.verticalShift(from: window(at: 50), to: window(at: 50), within: -90...90) == 0)
  #expect(GrayImage.meanDifference(window(at: 50), window(at: 50)) == 0)
  #expect((GrayImage.meanDifference(window(at: 50), window(at: 51)) ?? 0) > 30)
  // Too little would overlap.
  #expect(GrayImage.verticalShift(from: window(at: 0), to: window(at: 90), within: 85...95) == nil)
}

/// The Inventory screen, its scroll bar and the selected tile.
private struct Game {
  static let columns = 8
  static let firstColumn = 0.093
  static let columnPitch = 0.0765
  static let firstRow = 0.293
  static let rowPitch = 0.140
  static let viewTop = 0.18
  static let viewBottom = 0.90

  var pieces: [Artifact]
  /// How far the list has scrolled, in window heights.
  var scroll: Double
  var lineDistance = 0.031
  /// The wheel is the other way round.
  var reversed = false
  var selected = 0
  var clicks = 0
  var dropsClicks = false
  /// Pieces whose card can't be read.
  var unreadable: Set<Int> = []
  /// Pieces of a rarity Loupe doesn't save, read only by their text and level.
  var lowRarity: Set<Int> = []
  /// Moves the list up this far once, the wrong way, on the next scroll down.
  var jolt = 0.0

  var rowCount: Int { (pieces.count + Self.columns - 1) / Self.columns }
  var maximumScroll: Double {
    max(0, Self.firstRow + Double(rowCount - 1) * Self.rowPitch + 0.01 - Self.viewBottom)
  }

  func labelY(_ row: Int) -> Double { Self.firstRow + Double(row) * Self.rowPitch - scroll }

  /// The labels Vision reads, missing some.
  var labels: [GridLabel] {
    var labels: [GridLabel] = []
    for (index, piece) in pieces.enumerated() {
      let row = index / Self.columns
      let column = index % Self.columns
      let y = labelY(row)
      guard y >= Self.viewTop + 0.01, y + 0.007 <= Self.viewBottom,
        (index * 5 + Int(scroll * 1000)) % 9 != 4
      else { continue }
      labels.append(
        label("+\(piece.level)", x: Self.firstColumn + Double(column) * Self.columnPitch, y: y))
    }
    return labels
  }

  mutating func wheel(_ lines: Int) {
    let down = -(reversed ? -lines : lines)
    var move = Double(down) * lineDistance
    if down > 0 && jolt > 0 {
      move = -jolt
      jolt = 0
    }
    scroll = min(maximumScroll, max(0, scroll + move))
  }

  /// Marks the tiles past the end of the list, as the app does from the picture.
  func markVacant(_ grid: InventoryGrid) -> InventoryGrid {
    var grid = grid
    for row in grid.rows.indices {
      let place = Int(((grid.rows[row].y + scroll - Self.firstRow) / Self.rowPitch).rounded())
      for column in grid.columns.indices {
        grid.rows[row].vacant[column] = place * Self.columns + column >= pieces.count
      }
    }
    return grid
  }

  mutating func click(_ point: CGPoint) {
    clicks += 1
    if dropsClicks { return }
    let column = Int(((point.x - Self.firstColumn) / Self.columnPitch).rounded())
    let labelY = point.y + 0.35 * Self.rowPitch
    let row = Int(((labelY + scroll - Self.firstRow) / Self.rowPitch).rounded())
    guard point.y > Self.viewTop, point.y < Self.viewBottom, (0..<Self.columns).contains(column)
    else { return }
    let index = row * Self.columns + column
    if pieces.indices.contains(index) { selected = index }
  }
}

/// Runs a sweep to the end against `game`, measuring each scroll a little off.
private func sweep(_ game: inout Game, minimumLevel: Int = 1) throws -> InventorySweep {
  var known = try #require(InventoryGrid.detect(game.labels).map(game.markVacant))
  var sweep = InventorySweep(minimumLevel: minimumLevel, screen: known)
  var step = sweep.start()
  var steps = 0
  while true {
    steps += 1
    try #require(steps < 5000)
    switch step {
    case .finish: return sweep
    case .click(_, let point, _):
      // As the app does: a card that's still the one from before the click is unchanged.
      let shown = game.pieces[game.selected]
      game.click(point)
      let card = game.pieces[game.selected]
      step = sweep.clicked(
        game.unreadable.contains(game.selected)
          ? .unread
          : card.cardKey == shown.cardKey
            ? .unchanged
            : game.lowRarity.contains(game.selected)
              ? .other(key: "low " + card.cardKey, level: card.level) : .read(card))
    case .scroll(let lines, _):
      let before = game.scroll
      game.wheel(lines)
      let grid = InventoryGrid.detect(game.labels, known: known).map(game.markVacant)
      if let grid { known = grid }
      let error = (steps % 3 == 0 ? 1.0 : -1.0) * 0.004
      step = sweep.scrolled(to: grid, moved: game.scroll - before + error)
    }
  }
}

private func expectRead(_ sweep: InventorySweep, _ game: Game, count: Int, missed: Int = 0) {
  #expect(sweep.pieces.count == count)
  for (cell, artifact) in sweep.pieces {
    #expect(artifact == game.pieces[cell.row * Game.columns + cell.column])
  }
  #expect(sweep.missed.count == missed)
}

@Test func aSweepFindsTheTopAndReadsEveryLevelledPieceOnce() throws {
  let pieces =
    try (0..<30).map { try piece($0, level: 20) } + (30..<41).map { try piece($0, level: 16) }
    + (41..<90).map { try piece($0, level: 0) }
  var game = Game(pieces: pieces, scroll: 0.5)
  let result = try sweep(&game)
  #expect(result.ending == .belowMinimum)
  expectRead(result, game, count: 41)
  #expect(result.coveredLevels == Set(1...20))
  #expect(result.artifacts == Array(pieces.prefix(41)))
}

@Test func aSweepPassesOverPiecesOfOtherRaritiesAndStopsAtTheFirstPlusZero() throws {
  let pieces =
    try (0..<20).map { try piece($0, level: 20) } + (20..<35).map { try piece($0, level: 12) }
    + (35..<80).map { try piece($0, level: 0) }
  // Three-star pieces among the +12s, and the first +0.
  var game = Game(pieces: pieces, scroll: 0.3, lowRarity: [21, 24, 25, 33, 35])
  let result = try sweep(&game)
  #expect(result.ending == .belowMinimum)
  #expect(result.others.count == 4)
  #expect(Set(result.others.values) == [12])
  #expect(result.pieces.count == 31)
  #expect(
    !result.pieces.keys.contains { game.lowRarity.contains($0.row * Game.columns + $0.column) })
  #expect(result.missed.isEmpty)
  #expect(result.coveredLevels == Set(1...20))
}

@Test func aPlusZeroCardUnderAPositiveLabelDoesNotEndTheSweep() throws {
  let pieces =
    try (0..<20).map { try piece($0, level: 20) } + (20..<30).map { try piece($0, level: 8) }
    + (30..<70).map { try piece($0, level: 0) }
  var game = Game(pieces: pieces, scroll: 0)
  var known = try #require(InventoryGrid.detect(game.labels).map(game.markVacant))
  var sweep = InventorySweep(screen: known)
  var step = sweep.start()
  var misread = false
  for _ in 0..<2000 {
    switch step {
    case .finish: break
    case .click(_, let point, _):
      let shown = game.pieces[game.selected]
      game.click(point)
      var card = game.pieces[game.selected]
      // The card of tile 24 reads +0 though its label reads +8.
      if game.selected == 24 && !misread {
        misread = true
        card = try piece(24, level: 0)
      }
      step = sweep.clicked(card.cardKey == shown.cardKey ? .unchanged : .read(card))
      continue
    case .scroll(let lines, _):
      let before = game.scroll
      game.wheel(lines)
      let grid = InventoryGrid.detect(game.labels, known: known).map(game.markVacant)
      if let grid { known = grid }
      step = sweep.scrolled(to: grid, moved: game.scroll - before)
      continue
    }
    break
  }
  #expect(misread)
  #expect(sweep.ending == .belowMinimum)
  #expect(sweep.pieces.count == 29)
  #expect(sweep.missed == [InventorySweep.Cell(row: 3, column: 0)])
  #expect(!sweep.coveredLevels.contains(8))
  #expect(sweep.coveredLevels.contains(20))
}

@Test func aSweepLearnsAReversedWheel() throws {
  let pieces = try (0..<70).map { try piece($0, level: $0 < 50 ? 20 : 0) }
  for start in [0.0, 0.3] {
    var game = Game(pieces: pieces, scroll: start, reversed: true)
    let result = try sweep(&game)
    #expect(result.ending == .belowMinimum)
    expectRead(result, game, count: 50)
  }
}

@Test func aSweepReadsToTheEndOfAListThatEndsMidRow() throws {
  let pieces = try (0..<43).map { try piece($0, level: 20) }
  var game = Game(pieces: pieces, scroll: 0.2)
  let result = try sweep(&game)
  #expect(result.ending == .endOfList)
  expectRead(result, game, count: 43)
  #expect(result.coveredLevels == Set(0...20))
}

@Test func aSweepReadsAListThatFitsOnOneScreen() throws {
  let pieces = try (0..<13).map { try piece($0, level: 8) }
  var game = Game(pieces: pieces, scroll: 0)
  let result = try sweep(&game)
  #expect(result.ending == .endOfList)
  expectRead(result, game, count: 13)
  // The wheel never moved, so the sweep can't know it started at the top.
  #expect(result.coveredLevels.isEmpty)
}

@Test func anUnreadTileLeavesItsLevelsUncovered() throws {
  let pieces =
    try (0..<20).map { try piece($0, level: 20) } + (20..<30).map { try piece($0, level: 16) }
    + (30..<70).map { try piece($0, level: 0) }
  var game = Game(pieces: pieces, scroll: 0, unreadable: [25])
  let result = try sweep(&game)
  #expect(result.ending == .belowMinimum)
  expectRead(result, game, count: 29, missed: 1)
  #expect(result.coveredLevels == Set(17...20).union(1...15))
  #expect(!result.coveredLevels.contains(16))
}

@Test func aListThatMovesTheWrongWayStopsTheSweep() throws {
  let pieces = try (0..<90).map { try piece($0, level: 20) }
  var game = Game(pieces: pieces, scroll: 0)
  game.jolt = 0
  var known = try #require(InventoryGrid.detect(game.labels))
  var sweep = InventorySweep(minimumLevel: 1, screen: known)
  var step = sweep.start()
  var scrolledDown = 0
  for _ in 0..<2000 {
    switch step {
    case .finish(let ending):
      guard case .lostTrack = ending else {
        Issue.record("Expected lost track, got \(ending)")
        return
      }
      #expect(scrolledDown >= 1)
      return
    case .click(_, let point, _):
      game.click(point)
      step = sweep.clicked(.read(game.pieces[game.selected]))
    case .scroll(let lines, let expected):
      let before = game.scroll
      // Once reading, the second scroll down goes up instead.
      if let expected, expected > 0 {
        scrolledDown += 1
        if scrolledDown == 2 { game.jolt = 0.1 }
      }
      game.wheel(lines)
      let grid = InventoryGrid.detect(game.labels, known: known)
      if let grid { known = grid }
      step = sweep.scrolled(to: grid, moved: game.scroll - before)
    }
  }
  Issue.record("The sweep didn't finish")
}

@Test func anIdenticalCardBesideTheLastIsReadOnceADifferentCardIsUp() throws {
  // It looks like a click that didn't land until the next tile has shown its card.
  var pieces = try (0..<12).map { try piece($0, level: 20) }
  pieces[5] = try piece(4, level: 20)
  pieces += try (12..<20).map { try piece($0, level: 0) }
  var game = Game(pieces: pieces, scroll: 0)
  let result = try sweep(&game)
  #expect(result.ending == .belowMinimum)
  expectRead(result, game, count: 12)
}

@Test func aStaleCardBeforeTheFirstClickCantEndTheSweep() throws {
  // A +0 is selected, the first tiles are +20, and the first click doesn't land.
  let pieces =
    try (0..<16).map { try piece($0, level: 20) }
    + (16..<24).map {
      try piece($0, level: 0)
    }
  var game = Game(pieces: pieces, scroll: 0, selected: 20)
  var known = try #require(InventoryGrid.detect(game.labels).map(game.markVacant))
  var sweep = InventorySweep(minimumLevel: 1, screen: known)
  var step = sweep.start()
  var clicks = 0
  for _ in 0..<500 {
    switch step {
    case .finish:
      expectRead(sweep, game, count: 16)
      #expect(sweep.ending == .belowMinimum)
      return
    case .click(_, let point, _):
      let shown = game.pieces[game.selected]
      clicks += 1
      if clicks > 1 { game.click(point) }
      let card = game.pieces[game.selected]
      step = sweep.clicked(card.cardKey == shown.cardKey ? .unchanged : .read(card))
    case .scroll(let lines, _):
      let before = game.scroll
      game.wheel(lines)
      let grid = InventoryGrid.detect(game.labels, known: known).map(game.markVacant)
      if let grid { known = grid }
      step = sweep.scrolled(to: grid, moved: game.scroll - before)
    }
  }
  Issue.record("The sweep didn't finish")
}

@Test func anUnconfirmedLastTileLeavesTheLevelsBelowUncovered() throws {
  // Its card can't be read, so it could be any level up to the piece before it.
  let pieces = try (0..<10).map { try piece($0, level: 20) } + [try piece(10, level: 16)]
  var game = Game(pieces: pieces, scroll: 0, unreadable: [10])
  let result = try sweep(&game)
  #expect(result.ending == .endOfList)
  #expect(result.missed == [InventorySweep.Cell(row: 1, column: 2)])
  #expect(!result.coveredLevels.contains(16))
}

@Test func identicalCardsInDifferentTilesAreTwoPieces() throws {
  let copy = try piece(1, level: 20)
  var pieces = try (0..<20).map { try piece($0, level: 20) }
  pieces[9] = copy
  pieces[17] = copy
  pieces += try (20..<30).map { try piece($0, level: 0) }
  var game = Game(pieces: pieces, scroll: 0)
  let result = try sweep(&game)
  #expect(result.pieces.values.filter { $0.identity == copy.identity }.count == 3)
  #expect(result.pieces.count == 20)
}

@Test func clicksThatDontLandStopTheSweep() throws {
  let pieces = try (0..<40).map { try piece($0, level: 20) }
  var game = Game(pieces: pieces, scroll: 0, dropsClicks: true)
  let result = try sweep(&game)
  #expect(result.ending == .clicksNotLanding)
  #expect(result.pieces.count <= 2)
  #expect(game.clicks < 10)
}

@Test func anUnreadTileIsTriedTwiceThenSkipped() throws {
  let grid = try #require(
    InventoryGrid.detect([
      label("+20", x: 0.1, y: 0.3), label("+20", x: 0.2, y: 0.3), label("+20", x: 0.1, y: 0.4),
    ]))
  var sweep = InventorySweep(minimumLevel: 1, screen: grid)
  #expect(sweep.start() == .scroll(lines: 1, expected: nil))
  // Neither way moves.
  #expect(sweep.scrolled(to: grid, moved: 0) == .scroll(lines: -1, expected: nil))
  let first = sweep.scrolled(to: grid, moved: 0)
  guard case .click(let cell, _, _) = first else {
    Issue.record("Expected a click, got \(first)")
    return
  }
  #expect(sweep.clicked(.unread) == first)
  guard case .click(let next, _, _) = sweep.clicked(.unread) else {
    Issue.record("Expected the next tile")
    return
  }
  #expect(next != cell)
  #expect(sweep.missed == [cell])
  #expect(sweep.stop() == .finish(.stopped))
  #expect(sweep.coveredLevels.isEmpty)
}

@Test func aSweepMergeCountsCopiesAndReplacesALevelledRecord() throws {
  let kept = try piece(1, level: 20)
  let levelled = try piece(2, level: 16)
  let salvaged = try piece(3, level: 20)
  let below = try piece(4, level: 0)
  var inventory = Inventory()
  inventory.save(kept)
  inventory.save(levelled)
  inventory.save(salvaged)
  inventory.save(below)
  let copy = try piece(1, level: 20)
  let finished = try piece(2, level: 20)
  let fresh = try piece(5, level: 20)
  let result = inventory.mergeSweep([kept, copy, finished, fresh], covered: Set(1...20))
  #expect(result.read == 4)
  #expect(result.alreadySaved == 1)
  #expect(result.replaced == [levelled.id])
  #expect(result.added.count == 2)
  #expect(result.ambiguous.isEmpty)
  #expect(result.unseen.isEmpty)  // Set "d" wasn't in the sweep, as with a set filter.
  #expect(inventory.artifacts.count == 6)
  let replaced = try #require(inventory.artifacts.first { $0.id == levelled.id })
  #expect(replaced.level == 20)
  #expect(inventory.artifacts.contains { $0.id == below.id })

  // Read again: nothing changes.
  let again = inventory.mergeSweep([kept, copy, finished, fresh], covered: Set(1...20))
  #expect(again.alreadySaved == 4)
  #expect(again.added.isEmpty && again.replaced.isEmpty)
  #expect(inventory.artifacts.count == 6)
}

@Test func aSweepMergeMatchesAnImportedPieceWhateverItsRollRule() throws {
  let live = try piece(1, level: 16)
  let imported = try Artifact(
    setName: live.setName, slot: live.slot, main: live.main, level: live.level,
    substats: live.substats, rule: .special)
  var inventory = Inventory()
  inventory.save(imported)
  let result = inventory.mergeSweep([live], covered: Set(1...20))
  #expect(result.alreadySaved == 1)
  #expect(result.added.isEmpty && result.unseen.isEmpty)
  #expect(inventory.artifacts == [imported])
}

@Test func aSweepMergeListsWhatItCantDecide() throws {
  let first = try piece(1, level: 12)
  let second = try piece(1, level: 16)
  let gone = try piece(9, level: 20)
  var inventory = Inventory()
  inventory.save(first)
  inventory.save(second)
  inventory.save(gone)
  let finished = try piece(1, level: 20)
  // Either earlier record could have become it.
  var copy = inventory
  let result = copy.mergeSweep([finished], covered: Set(1...20))
  #expect(result.replaced.isEmpty)
  #expect(result.added.count == 1)
  #expect(result.ambiguous.first?.earlier.sorted() == [first.id, second.id].sorted())
  #expect(result.unseen.isEmpty)

  // Interrupted at +20: the lower records' levels weren't covered, so nothing is replaced.
  copy = inventory
  let partial = copy.mergeSweep([finished], covered: [])
  #expect(partial.replaced.isEmpty && partial.ambiguous.isEmpty && partial.unseen.isEmpty)

  // A record of a set the sweep saw, at a covered level, that it didn't see.
  copy = inventory
  let other = try piece(9, level: 16)
  let missing = copy.mergeSweep([other], covered: Set(16...20))
  #expect(missing.unseen == [gone.id])
}

@Test func aWheelThatNeverMovesTheListDoesntClaimTheEnd() throws {
  let pieces = try (0..<60).map { try piece($0, level: 20) }
  var game = Game(pieces: pieces, scroll: 0, lineDistance: 0)
  let result = try sweep(&game)
  guard case .lostTrack = result.ending else {
    Issue.record("Expected lost track, got \(String(describing: result.ending))")
    return
  }
  #expect(result.pieces.count == 40)
  #expect(result.coveredLevels.isEmpty)
}

@Test func aTilePutBackAndNeverRetriedIsUnread() throws {
  // The last +20 is an identical copy of the one before, so it's put back behind the next
  // tile, a +0 that ends the sweep.
  var pieces = try (0..<15).map { try piece($0, level: 20) }
  pieces.append(try piece(14, level: 20))
  pieces += try (16..<24).map { try piece($0, level: 0) }
  var game = Game(pieces: pieces, scroll: 0)
  let result = try sweep(&game)
  #expect(result.ending == .belowMinimum)
  #expect(result.missed == [InventorySweep.Cell(row: 1, column: 7)])
  #expect(!result.coveredLevels.contains(20))
}

@Test func anUnseenReturnToTheTopStopsTheSweep() throws {
  let grid = try #require(
    InventoryGrid.detect([
      label("+20", x: 0.1, y: 0.3), label("+20", x: 0.2, y: 0.3), label("+20", x: 0.1, y: 0.44),
    ]))
  let down = try #require(
    InventoryGrid.detect([
      label("+20", x: 0.1, y: 0.27), label("+20", x: 0.2, y: 0.27), label("+20", x: 0.1, y: 0.41),
    ]))
  var sweep = InventorySweep(minimumLevel: 1, screen: grid)
  _ = sweep.start()
  // Up doesn't move, down does: it was at the top, and goes back up a line.
  #expect(sweep.scrolled(to: grid, moved: 0) == .scroll(lines: -1, expected: nil))
  guard case .scroll(1, _) = sweep.scrolled(to: down, moved: 0.03) else {
    Issue.record("Expected a line back up")
    return
  }
  guard case .finish(.lostTrack) = sweep.scrolled(to: grid, moved: nil) else {
    Issue.record("Expected lost track")
    return
  }
}
