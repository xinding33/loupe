import Foundation

/// Original Resin spent farming an artifact domain, for turning expected drops into a cost.
public enum ResinCost {
  public static let perRun = 20.0
  /// Five-star artifacts per run of a top-level domain (Adventure Rank 45 and above): one
  /// guaranteed and about a 6.5% chance of a second. Condensed Resin doubles both sides.
  public static let fiveStarsPerRun = 1.065
  /// Natural regeneration: one Resin every eight minutes.
  public static let perDay = 180.0

  public static func runs(forDrops drops: Double) -> Double { drops / fiveStarsPerRun }
  public static func resin(forDrops drops: Double) -> Double { runs(forDrops: drops) * perRun }
  public static func days(forDrops drops: Double) -> Double { resin(forDrops: drops) / perDay }

  /// Days of natural Resin, or years past two years, rounded like `roughCount`.
  public static func duration(forDrops drops: Double) -> String {
    let days = days(forDrops: drops)
    if days < 0.5 { return "under a day" }
    if days < 730 {
      let count = roughCount(days)
      return "~\(count) \(count == "1" ? "day" : "days")"
    }
    return "~\(roughCount(days / 365)) years"
  }

  /// Resin and run counts behind `duration`, for a tooltip or detail line.
  public static func breakdown(forDrops drops: Double) -> String {
    "~\(roughCount(resin(forDrops: drops))) resin, ~\(roughCount(runs(forDrops: drops))) runs, "
      + "~\(roughCount(drops)) five-star drops"
  }
}
