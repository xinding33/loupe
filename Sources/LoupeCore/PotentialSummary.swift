/// Final ordinary-roll outcomes in the same score units as `Potential.currentScore`.
public struct PotentialSummary: Sendable, Equatable {
  public let p50Score: Double
  public let p90Score: Double
  public let bestPossibleScore: Double
}
