import Foundation

/// An evenly spaced grid of a captured frame's pixels, compared with the grid of the frame that
/// was last read to tell whether anything on screen has changed since.
public struct FrameSamples: Equatable, Sendable {
  /// The frame's size in pixels.
  public let width: Int
  public let height: Int
  /// Pixels between samples, in both directions.
  public let step: Int
  public let columns: Int
  public let rows: Int
  /// Blue + green + red of each sample, row by row.
  public let values: [UInt16]

  /// Samples per side of a cell. Squares of 2 x 2 cells, overlapping by a cell, are compared, so a
  /// change no larger than a cell always falls whole inside one square.
  public static let cell = 4
  /// The mean absolute difference per channel (0-255) of the most changed square at which a
  /// frame counts as changed. Streaming noise between captures of a still screen measured up to
  /// 1.1, and the smallest one-digit change on a card at least 10.6; see docs/status.md.
  public static let threshold = 3.0

  /// At least 1,280 samples across a 16:9 picture, which the game scales its text to, so a stroke
  /// of a card's digit, about two samples wide at any window size, can't fall between them.
  public static func step(width: Int, height: Int) -> Int {
    max(1, min(width / 1280, height / 720))
  }

  /// Samples 4-byte pixels whose first three bytes are color channels, such as BGRA. Rows may be
  /// padded past `width * 4` bytes. Returns nil for a frame that doesn't fit `bytes`.
  public init?(
    pixels bytes: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int,
    step: Int? = nil
  ) {
    let step = step ?? Self.step(width: width, height: height)
    guard width > 0, height > 0, step > 0, bytesPerRow >= width * 4,
      bytes.count >= bytesPerRow * (height - 1) + width * 4, let base = bytes.baseAddress
    else { return nil }
    let columns = width / step
    let rows = height / step
    let offset = step / 2
    let values = [UInt16](unsafeUninitializedCapacity: columns * rows) { output, count in
      for row in 0..<rows {
        let line = base + (row * step + offset) * bytesPerRow + offset * 4
        let start = row * columns
        for column in 0..<columns {
          let pixel = line + column * step * 4
          output[start + column] =
            UInt16(pixel.load(as: UInt8.self))
            + UInt16(pixel.load(fromByteOffset: 1, as: UInt8.self))
            + UInt16(pixel.load(fromByteOffset: 2, as: UInt8.self))
        }
      }
      count = columns * rows
    }
    self.init(
      width: width, height: height, step: step, columns: columns, rows: rows, values: values)
  }

  init(width: Int, height: Int, step: Int, columns: Int, rows: Int, values: [UInt16]) {
    self.width = width
    self.height = height
    self.step = step
    self.columns = columns
    self.rows = rows
    self.values = values
  }

  /// Whether this frame differs from `other` anywhere. A frame of another size always does.
  public func differs(from other: FrameSamples) -> Bool {
    guard let difference = largestDifference(from: other) else { return true }
    return difference >= Self.threshold
  }

  /// The mean absolute difference per channel of the most changed square, or nil when the two
  /// grids can't be compared.
  public func largestDifference(from other: FrameSamples, cell: Int = Self.cell) -> Double? {
    guard width == other.width, height == other.height, step == other.step,
      columns == other.columns, rows == other.rows, values.count == other.values.count,
      !values.isEmpty, cell > 0
    else { return nil }
    let cellColumns = (columns + cell - 1) / cell
    let cellRows = (rows + cell - 1) / cell
    var sums = [Int](repeating: 0, count: cellColumns * cellRows)
    values.withUnsafeBufferPointer { a in
      other.values.withUnsafeBufferPointer { b in
        sums.withUnsafeMutableBufferPointer { sums in
          for row in 0..<rows {
            let start = row * columns
            let cells = (row / cell) * cellColumns
            for cellColumn in 0..<cellColumns {
              var sum = 0
              for index in start + cellColumn * cell..<start
                + min(columns, cellColumn * cell + cell)
              {
                sum += abs(Int(a[index]) - Int(b[index]))
              }
              sums[cells + cellColumn] += sum
            }
          }
        }
      }
    }
    func samples(_ index: Int, _ count: Int, _ cells: Int) -> Int {
      index == cells - 1 ? count - index * cell : cell
    }
    var largest = 0.0
    for cellRow in 0..<max(1, cellRows - 1) {
      let lastRow = min(cellRow + 1, cellRows - 1)
      for cellColumn in 0..<max(1, cellColumns - 1) {
        let lastColumn = min(cellColumn + 1, cellColumns - 1)
        var sum = 0
        var count = 0
        for y in cellRow...lastRow {
          for x in cellColumn...lastColumn {
            sum += sums[y * cellColumns + x]
            count += samples(y, rows, cellRows) * samples(x, columns, cellColumns)
          }
        }
        largest = max(largest, Double(sum) / Double(count * 3))
      }
    }
    return largest
  }
}
