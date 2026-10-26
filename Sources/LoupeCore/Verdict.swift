import Foundation

public enum VerdictKind: String, Sendable, CaseIterable {
  case keep, level, review, fodder
}

/// One at-a-glance answer for an artifact: keep it, level it, look closer, or feed it.
/// It is advice only; nothing acts in the game.
public struct Verdict: Sendable, Equatable {
  public let kind: VerdictKind
  /// The checkpoint to level to next, for `.level`.
  public let targetLevel: Int?
  /// Chance an unfinished piece becomes a keeper at +20, when it has an ordinary forecast.
  public let keeperChance: Double?
  /// The character whose role drives the verdict, if any.
  public let characterID: String?
  /// That role, since a character can hold several.
  public let roleID: String?
  public let characterName: String?
  /// Why, without the character's name, so a narrow surface can show it beside the name.
  public let reason: String

  init(
    kind: VerdictKind, targetLevel: Int? = nil, keeperChance: Double? = nil,
    role: CharacterMatch?, reason: String
  ) {
    self.kind = kind
    self.targetLevel = targetLevel
    self.keeperChance = keeperChance
    self.characterID = role?.characterID
    self.roleID = role?.roleID
    self.characterName = role?.characterName
    self.reason = reason
  }

  /// The character it concerns, then the reason. The name leads so truncation cannot hide it.
  public var summary: String {
    characterName.map { "\($0) · \(reason)" } ?? reason
  }

  public var title: String {
    switch kind {
    case .keep: "Keep"
    case .level: "Level to +\(targetLevel ?? 20)"
    case .review: "Review"
    case .fodder: "Fodder"
    }
  }
}

/// Tunable defaults for verdicts. They are starting points, not reviewed thresholds.
public struct VerdictPolicy: Sendable {
  /// A piece is a keeper when a better one would take at least this many five-star domain drops.
  public var keepDrops: Double = 1000
  /// A piece among a role's best saved pieces also counts as a keeper when its share of new drops
  /// is at most this, so an empty or sparse saved pool does not keep weak pieces.
  public var gapShare: Double = 0.15
  /// Most saved pieces one stat-profile group can use at once.
  public var maxBackups = 3
  /// Smallest keeper chance that justifies leveling to the next checkpoint, indexed by the current
  /// checkpoint (+0, +4, +8, +12, +16). It rises because the last levels cost the most EXP.
  public var levelBars: [Double] = [0.05, 0.10, 0.15, 0.20, 0.30]

  public init() {}
  public static let standard = VerdictPolicy()
}

public enum VerdictEngine {
  /// Decides from the artifact's character matches and the saved +20 inventory.
  /// `excluding` removes the saved record of this same piece from comparisons.
  public static func evaluate(
    _ artifact: Artifact, matches: [CharacterMatch], inventory: [Artifact],
    excluding: UUID? = nil, policy: VerdictPolicy = .standard
  ) -> Verdict {
    let kind = "\(artifact.main.label) \(artifact.slot.plural)"
    guard !matches.isEmpty else {
      return Verdict(
        kind: .fodder, targetLevel: nil, keeperChance: nil, role: nil,
        reason: "No character role uses \(kind)")
    }
    let saved = inventory.filter {
      $0.id != (excluding ?? artifact.id) && $0.level == 20 && $0.slot == artifact.slot
        && $0.main == artifact.main
    }
    let roles = matches.map {
      RoleContext($0, artifact: artifact, saved: saved, matches: matches, policy: policy)
    }

    if artifact.level == 20 {
      return finished(artifact, roles: roles, kind: kind, policy: policy)
    }
    guard let outcomes = try? RollOutcomes(artifact) else {
      return Verdict(
        kind: .review, targetLevel: nil, keeperChance: nil, role: nil,
        reason: matches.compactMap(\.potentialUnavailableReason).first
          ?? "No ordinary forecast for this piece")
    }
    // Each role's keeper scores form an upper set, so one threshold per role decides every outcome.
    let thresholds = roles.map { $0.keeperThreshold(policy) }
    let chance = outcomes.probability { outcome in
      zip(roles, thresholds).contains { role, threshold in
        threshold.map { outcomes.score(outcome.units, profile: role.profile) >= $0 } ?? false
      }
    }
    let leading = zip(roles, thresholds).compactMap { role, threshold in
      threshold.map { minimum in
        (role, outcomes.probability { outcomes.score($0.units, profile: role.profile) >= minimum })
      }
    }.max { ($0.1, $0.0.setRank) < ($1.1, $1.0.setRank) }
    let bar = policy.levelBars[min(artifact.level / 4, policy.levelBars.count - 1)]
    if chance >= bar, chance > 0, let next = artifact.nextCheckpoint {
      let gap = leading.flatMap { lead in
        lead.0.rarity == nil ? lead.0.keeperReason(0, kind: kind, policy: policy) : nil
      }
      return Verdict(
        kind: .level, targetLevel: next, keeperChance: chance,
        role: leading?.0.match,
        reason: gap ?? "\(percentText(chance)) chance it becomes a keeper")
    }
    return Verdict(
      kind: .fodder, targetLevel: nil, keeperChance: chance,
      role: leading?.0.match,
      reason: chance == 0
        ? "Cannot become a keeper for any role"
        : "Only \(percentText(chance)) chance it becomes a keeper")
  }

  private static func finished(
    _ artifact: Artifact, roles: [RoleContext], kind: String, policy: VerdictPolicy
  ) -> Verdict {
    let scored = roles.map { ($0, $0.profile.score(artifact.substats)) }
    // Prefer the role that would take longest to replace, then one whose saved pool has a gap.
    let keepers = scored.compactMap { role, score in
      role.keeperReason(score, kind: kind, policy: policy).map { (role, $0, role.drops(score)) }
    }
    // Main-stat fits have no replacement estimate and rank below any drop-based reason.
    if let best = keepers.max(by: { ($0.2 ?? 0, $0.0.setRank) < ($1.2 ?? 0, $1.0.setRank) }) {
      return Verdict(
        kind: .keep, targetLevel: nil, keeperChance: nil, role: best.0.match,
        reason: best.1)
    }
    let graded = scored.filter { $0.0.rarity != nil }
    let leading = graded.min {
      ($0.0.rarity!.shareAtOrAbove($0.1), -$0.0.setRank)
        < ($1.0.rarity!.shareAtOrAbove($1.1), -$1.0.setRank)
    }
    if graded.count == scored.count,
      graded.allSatisfy({ $0.0.rarity!.shareAtOrAbove($0.1) > 0.5 })
    {
      return Verdict(
        kind: .fodder, targetLevel: nil, keeperChance: nil, role: nil,
        reason: "Bottom half of new \(kind) for every role")
    }
    if scored.allSatisfy({ role, score in role.saved.filter { $0 > score }.count >= role.backups })
    {
      return Verdict(
        kind: .fodder, targetLevel: nil, keeperChance: nil, role: nil,
        reason: "Enough saved \(kind) beat it for every role")
    }
    guard let (role, score) = leading, let rarity = role.rarity else {
      return Verdict(
        kind: .review, targetLevel: nil, keeperChance: nil, role: nil,
        reason: "Main-stat fit only; saved pieces already cover it")
    }
    let detail =
      role.saved.isEmpty
      ? "no saved +20 \(kind) to compare yet"
      : role.drops(score).map { "about \(roughCount($0)) drops to replace" } ?? ""
    return Verdict(
      kind: .review, targetLevel: nil, keeperChance: nil, role: role.match,
      reason: "Top \(percentText(rarity.shareAtOrAbove(score))) of new \(kind)"
        + (detail.isEmpty ? "" : "; \(detail)"))
  }
}

/// Per-role inputs: profile, rarity table, replacement odds, and the saved pool's scores.
private struct RoleContext {
  let match: CharacterMatch
  let profile: Profile
  /// Nil when no core substat can appear on this piece; the role then fits by main stat only.
  let rarity: DropRarity?
  /// An on-set role needs this set; an off-piece role accepts the slot and main from any set.
  let setChance: Double
  /// Saved +20 scores of the same slot and main stat, all sets, highest first.
  let saved: [Int]
  /// Saved pieces this role's stat-profile group can use at once, capped by the policy.
  let backups: Int

  init(
    _ match: CharacterMatch, artifact: Artifact, saved: [Artifact], matches: [CharacterMatch],
    policy: VerdictPolicy
  ) {
    self.match = match
    profile = match.profile
    let table = RarityCache.shared.rarity(artifact.slot, artifact.main, match.profile)
    rarity = (table?.bestScore ?? 0) > 0 ? table : nil
    setChance = match.setFit == .offPiece ? 1 : 0.5
    self.saved = saved.map { match.profile.score($0.substats) }.sorted(by: >)
    let group = matches.filter { $0.profile.weights == match.profile.weights }.count
    backups = min(max(1, group), policy.maxBackups)
  }

  /// Breaks ties toward roles that want this set: preferred, then alternative, then off-piece.
  var setRank: Int {
    switch match.setFit {
    case .preferred: 2
    case .alternative: 1
    case .offPiece: 0
    }
  }

  func drops(_ score: Int) -> Double? {
    guard let rarity else { return nil }
    return rarity.expectedDropsToBeat(score, setChance: setChance) ?? .infinity
  }

  func keeperReason(_ score: Int, kind: String, policy: VerdictPolicy) -> String? {
    guard let rarity else {
      // Main-stat fits have no substat ranking: keep while the saved pool has room.
      return saved.count < backups
        ? "Main stat fills a gap: \(saved.count) saved \(kind)" : nil
    }
    if let drops = drops(score), drops >= policy.keepDrops {
      return drops.isInfinite
        ? "No new drop beats it"
        : "About \(roughCount(drops)) drops to replace"
    }
    // Without saved pieces of this kind there is no gap to measure; see the baseline review.
    let better = saved.filter { $0 > score }.count
    guard !saved.isEmpty, better < backups, rarity.shareAtOrAbove(score) <= policy.gapShare
    else { return nil }
    if better > 0 { return "#\(better + 1) of saved \(kind)" }
    return saved.contains(score)
      ? "Tied for best of \(saved.count) saved \(kind)"
      : "Beats all \(saved.count) saved \(kind)"
  }

  /// Lowest final score that makes this role keep the piece, or nil when none does.
  func keeperThreshold(_ policy: VerdictPolicy) -> Int? {
    guard let rarity else {
      return keeperReason(0, kind: "", policy: policy) == nil ? nil : Int.min
    }
    var low = 0
    var high = rarity.bestScore
    guard keeperReason(high, kind: "", policy: policy) != nil else { return nil }
    while low < high {
      let middle = (low + high) / 2
      if keeperReason(middle, kind: "", policy: policy) != nil {
        high = middle
      } else {
        low = middle + 1
      }
    }
    return low
  }
}

/// Two significant figures with grouping, for counts that are only estimates.
public func roughCount(_ value: Double) -> String {
  guard value >= 100 else { return Int(value.rounded()).formatted() }
  let scale = pow(10, floor(log10(value)) - 1)
  return Int((value / scale).rounded() * scale).formatted()
}

private func percentText(_ value: Double) -> String {
  if value > 0 && value < 0.01 { return "<1%" }
  if value < 1 && value > 0.99 { return ">99%" }
  return Int((value * 100).rounded()).formatted() + "%"
}
