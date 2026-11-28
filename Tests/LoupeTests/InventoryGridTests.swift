import Foundation
import ImageIO
import LoupeCore
import Testing

@testable import Loupe

/// A snapshot of the Inventory screen, sorted by level, with every visible tile at +20 and a
/// five-star +20 card selected. Snapshots show the UID, so they stay outside the repository.
@Test(.enabled(if: ProcessInfo.processInfo.environment["LOUPE_GRID_SNAPSHOT"] != nil))
func aRecordedInventoryScreenGivesItsWholeGrid() throws {
  let path = try #require(ProcessInfo.processInfo.environment["LOUPE_GRID_SNAPSHOT"])
  let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
  let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  let left = try #require(GridReader.cardLeft(in: image))
  let grid = try #require(InventoryGrid.detect(GridReader.labels(in: image, left: left)))
  #expect(grid.columns.count == 8)
  #expect(grid.rows.count >= 5)
  let read = grid.rows.flatMap(\.levels).compactMap { $0 }
  print(
    "Grid: \(grid.columns.count) by \(grid.rows.count), \(read.count) labels, pitch \(grid.rowPitch)"
  )
  #expect(read.allSatisfy { $0 == 20 })
  #expect(read.count >= grid.columns.count * grid.rows.count * 9 / 10)
  // Every tile has its pale label strip; the band below the grid has none.
  let labels = GridReader.labels(in: image, left: left)
  let footer = try #require(GridReader.footer(labels))
  #expect(footer > grid.rows.last!.y + 0.02)
  let strips = GridReader.strips(in: image, columns: grid, above: footer)
  #expect(
    GridReader.markVacant(grid, in: image, strips: strips).rows.allSatisfy {
      !$0.vacant.contains(true)
    })
  // A tile judged by its strip is vacant without one; a row with no whole strip isn't judged.
  var gone = grid
  gone.rows[0].levels = Array(repeating: nil, count: grid.columns.count)
  #expect(GridReader.markVacant(gone, in: image, strips: []).rows[0].vacant.allSatisfy { !$0 })
  let strip = CGRect(
    x: grid.columns[0] - 0.3 * grid.columnPitch, y: grid.rows[0].y - 0.009,
    width: 0.6 * grid.columnPitch, height: 0.018)
  #expect((GridReader.stripShare(in: image, area: strip) ?? 0) > 0.5)
  #expect((GridReader.stripShare(in: image, area: strip.offsetBy(dx: 0, dy: 0.07)) ?? 1) < 0.2)
  let view = try #require(ScanView(grid))
  // The bar above the grid stays out of the picture the scroll is measured from.
  let header = try #require(GridReader.header(labels))
  #expect(
    grid.wholeRows(strips: strips, header: header, footer: footer) == Array(grid.rows.indices))
  let below = try #require(ScanView(grid, below: header, strips: strips))
  #expect(below.area.minY >= header)
  #expect(below.area.maxY <= view.area.maxY)
  let picture = try #require(view.picture(of: image))
  #expect(GrayImage.meanDifference(picture, picture) == 0)

  // The selected card reads in the background as the scan reads it, and holds still.
  let (card, note) = InventoryScanner.read(image)
  guard case .read(let artifact) = card else {
    Issue.record("The selected card wasn't read: \(note)")
    return
  }
  #expect(artifact.level == 20)
  let panel = CardView(left: left)
  let still = try #require(panel.picture(of: image))
  #expect(GrayImage.largestBlockDifference(still, still, block: 6) == 0)
  // The card is no part of the grid's picture, and the grid is no part of the card's.
  #expect(panel.area.minX > view.area.maxX - 0.01)
}

/// A snapshot of the Inventory scrolled to +4 pieces, with a +4 card selected, checked against
/// the grid of `LOUPE_GRID_SNAPSHOT`'s screen. One-digit labels mostly aren't read, so rows come
/// from the strips under them, and the card's level from a second pass over the card.
@Test(
  .enabled(
    if: ProcessInfo.processInfo.environment["LOUPE_PLUS4_SNAPSHOT"] != nil
      && ProcessInfo.processInfo.environment["LOUPE_GRID_SNAPSHOT"] != nil))
func aRecordedPlusFourScreenGivesItsRowsAndCard() throws {
  func image(_ key: String) throws -> CGImage {
    let path = try #require(ProcessInfo.processInfo.environment[key])
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }
  let top = try image("LOUPE_GRID_SNAPSHOT")
  let topLeft = try #require(GridReader.cardLeft(in: top))
  let known = try #require(InventoryGrid.detect(GridReader.labels(in: top, left: topLeft)))
  let screen = try image("LOUPE_PLUS4_SNAPSHOT")
  let left = try #require(GridReader.cardLeft(in: screen))
  let labels = GridReader.labels(in: screen, left: left)
  let footer = try #require(GridReader.footer(labels))
  let strips = GridReader.strips(in: screen, columns: known, above: footer)
  let grid = try #require(InventoryGrid.detect(labels, known: known, strips: strips))
  #expect(grid.columns.count == 8)
  #expect(grid.rows.count >= 5)
  #expect(grid.rows.flatMap(\.levels).compactMap { $0 }.allSatisfy { $0 == 4 })
  // Mid-list, the top row is cut off under the bar above the grid: the picture starts below it.
  let header = try #require(GridReader.header(labels))
  let view = try #require(ScanView(grid, below: header, strips: strips))
  #expect(view.area.minY >= header)
  #expect(view.area.maxY < 0.9)
  print("Picture rows \(view.area.minY)...\(view.area.maxY), header \(header)")
  let (card, note) = InventoryScanner.read(screen)
  guard case .read(let artifact) = card else {
    Issue.record("The +4 card wasn't read: \(note.prefix(60))")
    return
  }
  #expect(artifact.level == 4)
}

/// The pale buttons in the bar under the grid, on `LOUPE_PLUS4_SNAPSHOT`'s screen. A strip scan
/// that reached into the bar, to 0.95, took them for a row's strips: where the rows' spacing put
/// a row there, its first five tiles passed for tiles that brought up no card, and the other
/// three for vacant, so the scan ended at "the end of the list" mid-way through the +16 pieces.
@Test(
  .enabled(
    if: ProcessInfo.processInfo.environment["LOUPE_PLUS4_SNAPSHOT"] != nil
      && ProcessInfo.processInfo.environment["LOUPE_GRID_SNAPSHOT"] != nil))
func theBarUnderTheGridIsntARow() throws {
  func image(_ key: String) throws -> CGImage {
    let path = try #require(ProcessInfo.processInfo.environment[key])
    let source = try #require(CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil))
    return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  }
  let top = try image("LOUPE_GRID_SNAPSHOT")
  let topLeft = try #require(GridReader.cardLeft(in: top))
  let known = try #require(InventoryGrid.detect(GridReader.labels(in: top, left: topLeft)))
  let screen = try image("LOUPE_PLUS4_SNAPSHOT")
  let left = try #require(GridReader.cardLeft(in: screen))
  let labels = GridReader.labels(in: screen, left: left)
  let header = try #require(GridReader.header(labels))
  let footer = try #require(GridReader.footer(labels))
  let strips = GridReader.strips(in: screen, columns: known, above: footer)
  let grid = try #require(InventoryGrid.detect(labels, known: known, strips: strips))
  // The buttons' cream starts about 0.932 down this window, 0.037 tall to a strip's 0.021; the
  // last row's strip, cut off where the list fades out above the bar, isn't whole.
  print("Footer \(footer), lowest strip \(strips.max() ?? 0)")
  #expect(footer < 0.93)
  #expect(footer > (strips.max() ?? 1) + 0.02)

  // Scanned into the bar, as to 0.95 before, or right through it, the buttons are no strip.
  for bottom in [0.95, 0.99] {
    let reaching = GridReader.strips(in: screen, columns: known, above: bottom)
    #expect(reaching.allSatisfy { $0 < footer }, "to \(bottom): \(reaching)")
    #expect(reaching.count == strips.count)
  }

  // A lattice whose spacing puts a row in the bar, where a strip was found before, as on the
  // screen that ended the scan.
  let bar = 0.941
  let below = Int(((bar - grid.rows.last!.y) / grid.rowPitch).rounded(.up))
  let offset = bar - (grid.rows.last!.y + Double(below) * grid.rowPitch)
  var shifted = grid
  shifted.rows = (0..<(grid.rows.count + below)).map { index in
    InventoryGrid.Row(
      y: grid.rows[0].y + Double(index) * grid.rowPitch + offset,
      levels: Array(repeating: nil, count: grid.columns.count))
  }
  let last = shifted.rows.count - 1
  #expect(abs(shifted.rows[last].y - bar) < 1e-9)
  // Its tiles look as they did then: the first five pale, the rest vacant.
  let then = strips + [bar]
  let marked = GridReader.markVacant(shifted, in: screen, strips: then)
  #expect(marked.rows[last].vacant == [false, false, false, false, false, true, true, true])
  #expect(shifted.wholeRows(strips: then, header: header, footer: 1).contains(last))
  // Bounded by the bar, it's no row.
  #expect(!shifted.wholeRows(strips: then, header: header, footer: footer).contains(last))
}
