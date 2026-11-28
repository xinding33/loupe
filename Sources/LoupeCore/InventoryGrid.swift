import Foundation

/// Text read in the Inventory grid, in window coordinates from the top left, 0 to 1.
public struct GridLabel: Equatable, Sendable {
  public var text: String
  public var bounds: CGRect

  public init(text: String, bounds: CGRect) {
    self.text = text
    self.bounds = bounds
  }

  /// The level under a tile, or nil for other text. Vision reads "+20" as "20" or "-20" at times.
  public var level: Int? {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    guard trimmed.range(of: #"^[+\-]?\s?\d{1,2}$"#, options: .regularExpression) != nil,
      let value = Int(trimmed.filter(\.isNumber)), value <= 20
    else { return nil }
    return value
  }
}

/// The tiles of the Inventory grid on one screen, found from the level labels under them.
///
/// Rows and columns form a regular lattice, so a tile whose label Vision missed is still placed
/// between tiles whose labels it read.
public struct InventoryGrid: Equatable, Sendable {
  public struct Row: Equatable, Sendable {
    /// The middle of the row's level labels.
    public var y: Double
    /// The level read under each column's tile, nil where no label was read.
    public var levels: [Int?]
    /// Columns with no tile: no level label and none of the pale strip it sits on. Set by
    /// whoever has the picture.
    public var vacant: [Bool]

    public init(y: Double, levels: [Int?], vacant: [Bool]? = nil) {
      self.y = y
      self.levels = levels
      self.vacant = vacant ?? Array(repeating: false, count: levels.count)
    }
  }

  /// The middle of each column's level labels.
  public var columns: [Double]
  public var columnPitch: Double
  public var rowPitch: Double
  /// Top to bottom, including rows between read rows whose labels were all missed.
  public var rows: [Row]

  public init(columns: [Double], columnPitch: Double, rowPitch: Double, rows: [Row]) {
    self.columns = columns
    self.columnPitch = columnPitch
    self.rowPitch = rowPitch
    self.rows = rows
  }

  /// Where to click a tile: on its icon, above the label.
  public func tile(row: Int, column: Int) -> CGPoint {
    CGPoint(x: columns[column], y: rows[row].y - 0.35 * rowPitch)
  }

  /// The lattice through `labels`. `known` is the lattice of an earlier screen, kept as it is:
  /// columns don't move as the grid scrolls and rows keep their spacing, so a tile keeps the
  /// column it had, and rows whose labels were all missed can't change the spacing. Nil when
  /// the labels don't make a lattice.
  public static func detect(_ labels: [GridLabel], known: InventoryGrid? = nil) -> InventoryGrid? {
    let levels: [(bounds: CGRect, level: Int)] = labels.compactMap { label in
      label.level.map { (label.bounds, $0) }
    }
    guard !levels.isEmpty else { return nil }
    let height = median(levels.map { Double($0.bounds.height) })
    let width = median(levels.map { Double($0.bounds.width) })

    let columnPitch: Double
    let columnOrigin: Double
    let columnCount: Int
    let xs = clusters(levels.map { Double($0.bounds.midX) }, tolerance: max(0.004, 0.5 * width))
    if let known, known.columnPitch > 0, let first = known.columns.first {
      columnPitch = known.columnPitch
      columnOrigin = first
      columnCount = known.columns.count
    } else {
      guard let pitch = pitch(xs), let fit = lattice(xs, pitch: pitch) else { return nil }
      columnPitch = pitch
      columnOrigin = fit.origin
      columnCount = fit.count
    }

    let ys = clusters(levels.map { Double($0.bounds.midY) }, tolerance: max(0.004, 0.5 * height))
    let rowPitch: Double
    if let known, known.rowPitch > 0 {
      rowPitch = known.rowPitch
    } else if let measured = pitch(ys) {
      rowPitch = measured
    } else {
      return nil
    }
    guard let rowFit = lattice(ys, pitch: rowPitch) else { return nil }

    let columns = (0..<columnCount).map { columnOrigin + Double($0) * columnPitch }
    var rows = (0..<rowFit.count).map {
      Row(
        y: rowFit.origin + Double($0) * rowPitch, levels: Array(repeating: nil, count: columnCount))
    }
    for (bounds, level) in levels {
      guard let row = step(Double(bounds.midY), origin: rowFit.origin, pitch: rowPitch),
        let column = step(Double(bounds.midX), origin: columnOrigin, pitch: columnPitch),
        rows.indices.contains(row), (0..<columnCount).contains(column)
      else { continue }
      rows[row].levels[column] = level
    }
    return InventoryGrid(
      columns: columns, columnPitch: columnPitch, rowPitch: rowPitch, rows: rows)
  }

  /// Values within `tolerance` of their neighbor, merged into their mean, in order.
  static func clusters(_ values: [Double], tolerance: Double) -> [Double] {
    var groups: [[Double]] = []
    for value in values.sorted() {
      if let last = groups.last?.last, value - last <= tolerance {
        groups[groups.count - 1].append(value)
      } else {
        groups.append([value])
      }
    }
    return groups.map { $0.reduce(0, +) / Double($0.count) }
  }

  /// The spacing of a lattice through sorted `centers`: each gap is a whole number of pitches.
  static func pitch(_ centers: [Double]) -> Double? {
    guard centers.count >= 2 else { return nil }
    let gaps = zip(centers.dropFirst(), centers).map { $0 - $1 }
    guard let unit = gaps.min(), unit > 0 else { return nil }
    var spans = 0.0
    for gap in gaps {
      let count = (gap / unit).rounded()
      guard abs(gap - count * unit) < 0.2 * unit else { return nil }
      spans += count
    }
    return gaps.reduce(0, +) / spans
  }

  /// The first lattice position through sorted `centers` and how many positions they span. Nil
  /// when a center is off the lattice.
  static func lattice(_ centers: [Double], pitch: Double) -> (origin: Double, count: Int)? {
    guard let first = centers.first, pitch > 0 else { return nil }
    let steps = centers.map { (($0 - first) / pitch).rounded() }
    let origin = zip(centers, steps).map { $0 - $1 * pitch }.reduce(0, +) / Double(centers.count)
    guard zip(centers, steps).allSatisfy({ abs($0 - origin - $1 * pitch) < 0.25 * pitch }),
      let last = steps.last
    else { return nil }
    return (origin, Int(last) + 1)
  }

  private static func step(_ value: Double, origin: Double, pitch: Double) -> Int? {
    let step = ((value - origin) / pitch).rounded()
    guard abs(value - origin - step * pitch) < 0.3 * pitch else { return nil }
    return Int(step)
  }

  private static func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
  }
}

/// A grayscale picture of the grid, for measuring how far it scrolled.
public struct GrayImage: Equatable, Sendable {
  public let width: Int
  public let height: Int
  /// Row by row from the top.
  public let pixels: [UInt8]

  public init(width: Int, height: Int, pixels: [UInt8]) {
    precondition(pixels.count == width * height)
    self.width = width
    self.height = height
    self.pixels = pixels
  }

  /// The average difference between two pictures of the same size, 0 to 255. Nil for pictures
  /// of different sizes.
  public static func meanDifference(_ a: GrayImage, _ b: GrayImage) -> Double? {
    guard a.width == b.width, a.height == b.height, !a.pixels.isEmpty else { return nil }
    let total = zip(a.pixels, b.pixels).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
    return Double(total) / Double(a.pixels.count)
  }

  /// How many rows the content moved up from `before` to `after`: row y of `after` shows what
  /// row y + shift of `before` showed. Searched within `range`, keeping at least a fifth of the
  /// picture overlapping. Nil when no shift in range leaves that much.
  public static func verticalShift(
    from before: GrayImage, to after: GrayImage, within range: ClosedRange<Int>
  ) -> Int? {
    guard before.width == after.width, before.height == after.height, before.width > 0 else {
      return nil
    }
    let width = before.width
    let height = before.height
    let minimumOverlap = max(1, height / 5)
    var best: (shift: Int, difference: Double)?
    for shift in range {
      let overlap = height - abs(shift)
      guard overlap >= minimumOverlap else { continue }
      let first = max(0, -shift)
      var total = 0
      for y in first..<(first + overlap) {
        let a = (y + shift) * width
        let b = y * width
        for x in 0..<width {
          total += abs(Int(before.pixels[a + x]) - Int(after.pixels[b + x]))
        }
      }
      let difference = Double(total) / Double(overlap * width)
      // Of equally good shifts, the smallest move is the likeliest.
      if best == nil || difference < best!.difference - 1e-9
        || (abs(difference - best!.difference) <= 1e-9 && abs(shift) < abs(best!.shift))
      {
        best = (shift, difference)
      }
    }
    return best?.shift
  }
}
