import Testing

@testable import LoupeCore

struct ResinCostTests {
  @Test func dropsConvertToRunsResinAndDays() {
    let drops = ResinCost.fiveStarsPerRun * 9
    #expect(abs(ResinCost.runs(forDrops: drops) - 9) < 1e-9)
    #expect(abs(ResinCost.resin(forDrops: drops) - 180) < 1e-9)
    #expect(abs(ResinCost.days(forDrops: drops) - 1) < 1e-9)
  }

  @Test func durationReadsAsDaysThenYears() {
    #expect(ResinCost.duration(forDrops: 2) == "under a day")
    #expect(ResinCost.duration(forDrops: 9.6) == "~1 day")
    #expect(ResinCost.duration(forDrops: 110) == "~11 days")
    #expect(ResinCost.duration(forDrops: 6234) == "~650 days")
    #expect(ResinCost.duration(forDrops: 100_000) == "~29 years")
  }

  @Test func durationBoundariesRoundAndPluralise() {
    let perDay = ResinCost.perDay / ResinCost.perRun * ResinCost.fiveStarsPerRun
    #expect(ResinCost.duration(forDrops: perDay * 0.49) == "under a day")
    #expect(ResinCost.duration(forDrops: perDay * 0.51) == "~1 day")
    #expect(ResinCost.duration(forDrops: perDay * 1.49) == "~1 day")
    #expect(ResinCost.duration(forDrops: perDay * 1.51) == "~2 days")
    #expect(ResinCost.duration(forDrops: perDay * 729) == "~730 days")
    #expect(ResinCost.duration(forDrops: perDay * 731) == "~2 years")
  }

  @Test func breakdownRoundsEachCount() {
    #expect(
      ResinCost.breakdown(forDrops: 110) == "~2,100 resin, ~100 runs, ~110 five-star drops")
  }
}
