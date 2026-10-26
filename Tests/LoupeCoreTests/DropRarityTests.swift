import Foundation
import LoupeCore
import Testing

struct DropRarityTests {
  private static let furina = Profile(
    "furina", weights: [.hpPercent: 100, .critRate: 100, .critDamage: 100])
  private static let itto = Profile(
    "itto", weights: [.defPercent: 100, .critRate: 100, .critDamage: 100])
  private static let em = Profile("em", weights: [.elementalMastery: 100])

  /// Deterministic generator so the simulation is reproducible.
  private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state &+= 0x9E37_79B9_7F4A_7C15
      var z = state
      z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
      z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
      return z ^ (z >> 31)
    }
  }

  /// Plays out drops as the game does: three-line starts reveal a fourth line at +4.
  private static func simulate(
    _ slot: Slot, _ main: Stat, _ profile: Profile, source: DropSource, count: Int
  ) -> [Int] {
    var rng = SplitMix(state: 0x5EED)
    func pick(_ excluded: [Stat]) -> Stat {
      let pool = Stat.substats.filter { $0 != main && !excluded.contains($0) }
      var roll = Int.random(in: 0..<pool.reduce(0) { $0 + $1.appearanceWeight }, using: &rng)
      for stat in pool {
        roll -= stat.appearanceWeight
        if roll < 0 { return stat }
      }
      return pool.last!
    }
    return (0..<count).map { _ in
      let fourLines = Double.random(in: 0..<1, using: &rng) < source.fourLineChance
      var lines: [Stat] = []
      var units: [Int] = []
      for _ in 0..<(fourLines ? 4 : 3) {
        lines.append(pick(lines))
        units.append(Int.random(in: 7...10, using: &rng))
      }
      for _ in 0..<5 {
        if lines.count < 4 {
          lines.append(pick(lines))
          units.append(Int.random(in: 7...10, using: &rng))
        } else {
          units[Int.random(in: 0..<4, using: &rng)] += Int.random(in: 7...10, using: &rng)
        }
      }
      return zip(lines, units).reduce(0) { $0 + $1.1 * profile.weights[$1.0, default: 0] }
    }
  }

  @Test(arguments: [
    (Slot.flower, Stat.hp, "furina", DropSource.domain),
    (.goblet, .hydroDamage, "furina", .bossOrStrongbox),
    (.sands, .defPercent, "itto", .domain),
    (.plume, .atk, "em", .domain),
  ])
  func exactSharesMatchASimulationOfTheDropProcess(
    slot: Slot, main: Stat, profileID: String, source: DropSource
  ) throws {
    let profile = [Self.furina, Self.itto, Self.em].first { $0.id == profileID }!
    let rarity = try DropRarity(slot: slot, main: main, profile: profile, source: source)
    let count = 200_000
    let simulated = Self.simulate(slot, main, profile, source: source, count: count)
    #expect(abs(rarity.probabilities.reduce(0, +) - 1) < 1e-9)
    for threshold in [1000, 2000, 3000, 4000, 5000, 6000] {
      let observed = Double(simulated.filter { $0 >= threshold }.count) / Double(count)
      #expect(abs(rarity.shareAtOrAbove(threshold) - observed) < 0.005)
    }
  }

  @Test func bestScoresFollowTheLinesTheMainLeavesAvailable() throws {
    // Three core lines can start on a flower, then take all five upgrades.
    #expect(try DropRarity(slot: .flower, main: .hp, profile: Self.furina).bestScore == 8000)
    // An HP% main removes HP% from the substats, leaving two core lines.
    #expect(try DropRarity(slot: .sands, main: .hpPercent, profile: Self.furina).bestScore == 7000)
    #expect(try DropRarity(slot: .flower, main: .hp, profile: Self.em).bestScore == 6000)
    #expect(
      try DropRarity(slot: .goblet, main: .elementalMastery, profile: Self.em).bestScore == 0)
  }

  @Test func sharesAreMonotoneAndTiesCount() throws {
    let rarity = try DropRarity(slot: .circlet, main: .critRate, profile: Self.furina)
    #expect(rarity.shareAtOrAbove(Int.min) == 1)
    #expect(rarity.shareAtOrAbove(rarity.scores.first!) == 1)
    #expect(rarity.shareAtOrAbove(rarity.bestScore + 1) == 0)
    #expect(rarity.shareAbove(rarity.bestScore) == 0)
    let shares = stride(from: 0, through: rarity.bestScore, by: 100).map {
      rarity.shareAtOrAbove($0)
    }
    #expect(zip(shares, shares.dropFirst()).allSatisfy { $0 >= $1 })
  }

  @Test func replacementDropsUseSetSlotMainAndSubstatOdds() throws {
    let flower = try DropRarity(slot: .flower, main: .hp, profile: Self.furina)
    // Any on-set flower beats a score below every outcome: one in ten domain drops.
    #expect(abs(flower.expectedDropsToBeat(-1)! - 10) < 1e-9)
    #expect(flower.expectedDropsToBeat(flower.bestScore) == nil)
    let emGoblet = try DropRarity(slot: .goblet, main: .elementalMastery, profile: Self.furina)
    #expect(abs(emGoblet.expectedDropsToBeat(-1)! - 400) < 1e-9)
    let share = flower.shareAbove(5000)
    #expect(abs(flower.expectedDropsToBeat(5000)! - 10 / share) < 1e-6)
  }

  @Test func fourLineStartsFromBossesRaiseHighShares() throws {
    let domain = try DropRarity(slot: .flower, main: .hp, profile: Self.furina, source: .domain)
    let boss = try DropRarity(
      slot: .flower, main: .hp, profile: Self.furina, source: .bossOrStrongbox)
    #expect(boss.shareAtOrAbove(6000) > domain.shareAtOrAbove(6000))
    #expect(domain.shareAtOrAbove(9000) == 0)
  }

  @Test func invalidMainForTheSlotThrows() {
    #expect(throws: ArtifactError.self) {
      try DropRarity(slot: .sands, main: .critRate, profile: Self.furina)
    }
  }
}
