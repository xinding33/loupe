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

@Test func aScrollIsMeasuredFromThePictures() throws {
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
  // A move outside the range searched still has a best shift, but a poor one.
  let exact = try #require(
    GrayImage.bestShift(from: window(at: 50), to: window(at: 73), within: -90...90))
  #expect(exact.shift == 23 && exact.difference == 0)
  let outside = try #require(
    GrayImage.bestShift(from: window(at: 50), to: window(at: 73), within: 0...15))
  #expect(outside.difference > 8)
}

@Test func oneChangedDigitStandsOutInItsBlock() {
  let width = 64
  let height = 64
  let blank = GrayImage(width: width, height: height, pixels: Array(repeating: 40, count: 4096))
  var pixels = blank.pixels
  // A 4 by 6 glyph turned from dark to light, as when "3.5" becomes "3.9".
  for y in 17..<23 { for x in 33..<37 { pixels[y * width + x] = 200 } }
  let digit = GrayImage(width: width, height: height, pixels: pixels)
  #expect((GrayImage.meanDifference(blank, digit) ?? 0) < 1)
  #expect((GrayImage.largestBlockDifference(blank, digit) ?? 0) > 50)
  // Noise spread everywhere doesn't.
  let noisy = GrayImage(
    width: width, height: height,
    pixels: blank.pixels.enumerated().map { $0.offset % 3 == 0 ? 43 : 40 })
  #expect((GrayImage.largestBlockDifference(blank, noisy) ?? 99) < 2)
  #expect(
    GrayImage.largestBlockDifference(blank, GrayImage(width: 1, height: 1, pixels: [0])) == nil)
}

@Test func labelStripsGiveRowsWithoutTheirLabels() throws {
  // Strips eight lines tall every twenty lines, the last cut off by the edge.
  var share = Array(repeating: 0.0, count: 100)
  for start in [10, 30, 50, 70] { for y in start..<(start + 8) { share[y] = 1 } }
  for y in 90..<93 { share[y] = 1 }
  let middles = InventoryGrid.strips(share, top: 0.2, step: 0.01)
  #expect(middles.count == 4)
  #expect(abs(middles[0] - 0.34) < 1e-9)
  // Something pale four times as tall, as the buttons in the bar under the grid, isn't a strip,
  // nor is a strip cut off by either end of what was scanned.
  var bar = share
  for y in 82..<98 { bar[y] = 0.4 }
  #expect(InventoryGrid.strips(bar, top: 0.2, step: 0.01) == middles)
  var ends = share
  for y in 0..<5 { ends[y] = 1 }
  for y in 95..<100 { ends[y] = 0.5 }
  #expect(InventoryGrid.strips(ends, top: 0.2, step: 0.01) == middles)
  // A screen where only one label was read still has every row, from a known lattice.
  let known = try #require(
    InventoryGrid.detect([
      label("+20", x: 0.1, y: 0.34), label("+20", x: 0.2, y: 0.34), label("+20", x: 0.1, y: 0.54),
    ]))
  let grid = try #require(
    InventoryGrid.detect([label("+4", x: 0.2, y: 0.54)], known: known, strips: middles))
  #expect(grid.rows.count == 4)
  #expect(grid.rows[1].levels == [nil, 4])
  #expect(label("†4", x: 0, y: 0).level == 4)
}

@Test func onlyRowsBetweenTheBarsAreWhole() throws {
  // As on the screen that ended a scan mid-list: rows every 0.14 from 0.4012, and pale buttons
  // in the bar under the grid, from 0.932, falling on the spacing a row below the last.
  let ys = [0.4012, 0.5412, 0.6813, 0.8213]
  let labels = ys.flatMap { y in [label("+16", x: 0.1, y: y), label("+16", x: 0.2, y: y)] }
  let grid = try #require(InventoryGrid.detect(labels, known: nil, strips: []))
  let known = try #require(
    InventoryGrid.detect(labels, known: grid, strips: ys + [0.941]))
  #expect(known.rows.count == 5)
  let strips = ys + [0.941]
  // Under the bar above the grid, at 0.17, and above the bar under it.
  #expect(known.wholeRows(strips: strips, header: 0.17, footer: 1) == [0, 1, 2, 3, 4])
  #expect(known.wholeRows(strips: strips, header: 0.17, footer: 0.92) == [0, 1, 2, 3])
  // A row cut off under the bar above isn't whole, nor one without its strip.
  #expect(known.wholeRows(strips: strips, header: 0.32, footer: 0.92) == [1, 2, 3])
  #expect(known.wholeRows(strips: Array(ys.dropFirst()), header: 0.17, footer: 0.92) == [1, 2, 3])
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
