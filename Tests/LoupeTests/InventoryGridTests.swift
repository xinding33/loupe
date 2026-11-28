import Foundation
import ImageIO
import LoupeCore
import Testing

@testable import Loupe

/// A snapshot of the Inventory screen, five-star filter, sorted by level, with every visible
/// tile at +20. Snapshots show the UID, so they stay outside the repository.
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
  #expect(GridReader.markVacant(grid, in: image).rows.allSatisfy { !$0.vacant.contains(true) })
  let strip = CGRect(
    x: grid.columns[0] - 0.3 * grid.columnPitch, y: grid.rows[0].y - 0.009,
    width: 0.6 * grid.columnPitch, height: 0.018)
  #expect((GridReader.stripShare(in: image, area: strip) ?? 0) > 0.5)
  #expect((GridReader.stripShare(in: image, area: strip.offsetBy(dx: 0, dy: 0.07)) ?? 1) < 0.2)
  let view = try #require(ScanView(grid))
  let picture = try #require(view.picture(of: image))
  #expect(view.shift(from: picture, to: picture, expected: nil) == 0)
}
