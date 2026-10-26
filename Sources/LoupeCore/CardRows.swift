import CoreGraphics

public enum CardRows {
  /// Joins text that Vision split within one row, such as "CRIT" and "DMG+12.4%", and returns
  /// the rows top to bottom. Bounds are normalized with a bottom-left origin. Only close
  /// neighbours join, and a bare number never does: the main-stat value stays its own line even
  /// beside a long label such as "Hydro DMG Bonus".
  public static func joined(_ regions: [TextRegion], maxGap: Double = 0.03) -> [TextRegion] {
    var rows: [TextRegion] = []
    for region in regions.sorted(by: { $0.bounds.minX < $1.bounds.minX }) {
      let bare = region.text.range(of: #"^\d[\d,.]*%?$"#, options: .regularExpression) != nil
      let row = rows.lastIndex { row in
        guard !bare else { return false }
        let overlap =
          min(row.bounds.maxY, region.bounds.maxY) - max(row.bounds.minY, region.bounds.minY)
        let gap = region.bounds.minX - row.bounds.maxX
        return overlap > min(row.bounds.height, region.bounds.height) / 2 && gap > -0.005
          && gap < maxGap
      }
      if let row {
        rows[row] = TextRegion(
          text: rows[row].text + " " + region.text, bounds: rows[row].bounds.union(region.bounds),
          confidence: min(rows[row].confidence, region.confidence))
      } else {
        rows.append(region)
      }
    }
    return rows.sorted { $0.bounds.midY > $1.bounds.midY }
  }
}
