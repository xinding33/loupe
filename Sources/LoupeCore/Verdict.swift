import Foundation

public enum VerdictKind: String, Sendable, CaseIterable {
  case keep, level, review, fodder
}

/// Whether a role still has a use for the piece.
public enum RoleStanding: Sendable, Equatable {
  case open
  /// This many saved pieces the role would wear instead already beat the piece's best outcome.
  case covered(Int)
  /// An off-set flower or plume: a 4+1 build's off-piece is rarely that slot.
  case rareOffPiece
}

/// One at-a-glance answer for an artifact: keep it, level it, look closer, or feed it.
/// It is advice only; nothing acts in the game.
public struct Verdict: Sendable, Equatable {
  public let kind: VerdictKind
  /// The checkpoint to level to, for `.level`.
  public let targetLevel: Int?
  /// The grade behind the verdict, when a graded role drives it.
  public let grade: ArtifactTier?
  /// Chance an unfinished piece finishes A or better for that role.
  public let chanceOfAOrBetter: Double?
  /// The character whose role drives the verdict, if any.
  public let characterID: String?
  /// That role, since a character can hold several.
  public let roleID: String?
  public let roleName: String?
  public let characterName: String?
  /// Why, without the character's name, so a narrow surface can show it beside the name.
  public let reason: String
  /// Each role's standing by role ID. Roles missing from it are open.
  public internal(set) var standings: [String: RoleStanding] = [:]

  init(kind: VerdictKind, targetLevel: Int? = nil, role: RoleContext? = nil, reason: String) {
    self.init(kind: kind, targetLevel: targetLevel, match: role?.match, reason: reason)
  }

  init(kind: VerdictKind, targetLevel: Int? = nil, match: CharacterMatch?, reason: String) {
    self.kind = kind
    self.targetLevel = targetLevel
    self.grade = match?.grades?.grade
    self.chanceOfAOrBetter = match?.grades?.chanceOfAOrBetter
    self.characterID = match?.characterID
    self.roleID = match?.roleID
    self.roleName = match?.roleName
    self.characterName = match?.characterName
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
  /// Most saved pieces one stat-profile group can use at once.
  public var maxBackups = 3
  /// Four-star pieces of one set, slot and main stat worth saving: one or two sets of a support
  /// set such as Instructor cover an account.
  public var fourStarCopies = 2

  public init() {}
  public static let standard = VerdictPolicy()
}

/// Verdicts follow the best roll grade among the piece's roles (`RollGrade`). A main-stat-only
/// fit whose saved pool has room ranks below S and A and above B.
/// - Unfinished: S levels to +20. A and B level to the next checkpoint, where the grade is read
///   again, so EXP follows the rolls. C and D are fodder unless the saved pool is thin but not
///   empty. Main-stat-only fits level while the pool has room. Supports, roles without both crit
///   stats, mostly need their main stat, and a flower suits nearly every support, so a support's
///   grade levels a piece only at S.
/// - Finished: S and A are kept. B, or A or B for a support, is kept while it ranks among the
///   saved pieces a role can use and reviewed when nothing is saved. C is reviewed only when that
///   pool is thin but not empty, and D is fodder.
/// A role is set aside when enough saved +20 pieces of the same slot and main stat already beat
/// the piece's best outcome for it. An on-set role counts only saved pieces of this set, which
/// are what it would wear instead; an off-piece role counts every set. An off-set flower or
/// plume is set aside too, since a 4+1 build rarely takes its off-piece in that slot.
public enum VerdictEngine {
  /// Decides from the artifact's character matches and the saved +20 inventory.
  /// `excluding` removes the saved record of this same piece from comparisons.
  public static func evaluate(
    _ artifact: Artifact, matches: [CharacterMatch], inventory: [Artifact],
    excluding: UUID? = nil, policy: VerdictPolicy = .standard
  ) -> Verdict {
    var standings: [String: RoleStanding] = [:]
    var verdict =
      artifact.rarity == 4
      ? fourStar(
        artifact, matches: matches, inventory: inventory, excluding: excluding, policy: policy,
        standings: &standings)
      : ordinary(
        artifact, matches: matches, inventory: inventory, excluding: excluding, policy: policy,
        standings: &standings)
    verdict.standings = standings
    return verdict
  }

  private static func ordinary(
    _ artifact: Artifact, matches: [CharacterMatch], inventory: [Artifact], excluding: UUID?,
    policy: VerdictPolicy, standings: inout [String: RoleStanding]
  ) -> Verdict {
    let kind = "\(artifact.main.label) \(artifact.slot.plural)"
    guard !matches.isEmpty else {
      return Verdict(kind: .fodder, reason: "No character role uses \(kind)")
    }
    let saved = inventory.filter {
      $0.id != (excluding ?? artifact.id) && $0.level == 20 && $0.slot == artifact.slot
        && $0.main == artifact.main
    }
    let roles = matches.map {
      RoleContext($0, artifact: artifact, saved: saved, matches: matches, policy: policy)
    }
    // Set and slot alone set aside an off-set flower or plume, even without a forecast.
    for role in roles where role.rareOffPiece { standings[role.match.roleID] = .rareOffPiece }
    let outcomes = artifact.level == 20 ? nil : try? RollOutcomes(artifact)
    if artifact.level < 20 && outcomes == nil {
      return Verdict(
        kind: .review,
        reason: matches.compactMap(\.potentialUnavailableReason).first
          ?? "No ordinary forecast for this piece")
    }
    // The best this piece can score for each role: its final score, or its best outcome. Roles
    // sharing an archetype share weights, so each weight profile is scored once.
    var bests: [[Stat: Int]: Int] = [:]
    func ceiling(_ role: RoleContext) -> Int {
      if let known = bests[role.profile.weights] { return known }
      let value: Int
      if let outcomes {
        let weights = outcomes.stats.map { role.profile.weights[$0, default: 0] }
        value =
          outcomes.outcomes.lazy.map { zip(weights, $0.units).reduce(0) { $0 + $1.0 * $1.1 } }
          .max() ?? 0
      } else {
        value = role.profile.score(artifact.substats)
      }
      bests[role.profile.weights] = value
      return value
    }
    for role in roles { standings[role.match.roleID] = role.standing(best: ceiling(role)) }
    let open = roles.filter { standings[$0.match.roleID] == .open }
    guard !open.isEmpty else {
      if roles.allSatisfy(\.rareOffPiece) {
        return Verdict(
          kind: .fodder,
          reason:
            "No role runs \(artifact.setName); off-set \(artifact.slot.plural) are rarely worn")
      }
      let worn = roles.filter { !$0.rareOffPiece }
      let pool = worn.allSatisfy { $0.match.scope == .sameSet } ? worn[0].kind : kind
      let beaten = outcomes == nil ? "beat it" : "beat its best outcome"
      let users = worn.count < roles.count ? "every role on this set" : "every role"
      return Verdict(kind: .fodder, reason: "Enough saved \(pool) \(beaten) for \(users)")
    }
    // The best letter leads, then the role likelier to wear it, then the rarer result for it:
    // more drops to replace a finished piece, or a likelier A for an unfinished one.
    func rarity(_ role: RoleContext) -> Double {
      outcomes == nil
        ? role.drops(role.profile.score(artifact.substats)) ?? 0
        : role.match.grades?.chanceOfAOrBetter ?? 0
    }
    func strongest(_ roles: [RoleContext]) -> RoleContext? {
      roles.filter { $0.grade != nil }.min {
        ($0.tierRank, -$0.wearRank, -rarity($0)) < ($1.tierRank, -$1.wearRank, -rarity($1))
      }
    }
    // A support's grade counts only at S; below that it can still keep a finished piece that
    // ranks among the saved ones.
    let leading = strongest(open.filter { !$0.isSupport || $0.grade == .s })
    let support = strongest(open.filter(\.isSupport)).flatMap {
      $0.tierRank < (leading?.tierRank ?? .max) ? $0 : nil
    }
    let gap = open.filter { $0.grade == nil && $0.saved.count < $0.backups }.max {
      $0.wearRank < $1.wearRank
    }
    // Any C role whose saved pool is thin can rescue the piece; supports only once it is
    // finished, since their grade levels only at S. An empty pool usually means the bag was not
    // scanned, so it does not make a C piece worth it.
    let thin = strongest(
      open.filter {
        $0.grade == .c && !$0.saved.isEmpty && $0.saved.count < $0.backups
          && (outcomes == nil || !$0.isSupport)
      })
    let mainFit = { (role: RoleContext) in
      "Main stat fills a gap: \(role.saved.count) saved \(role.kind)"
    }
    let fodder = Verdict(
      kind: .fodder, role: leading,
      reason: leading.map { $0.grade == .c ? "C at best for every role" : "D for every role" }
        ?? "Main-stat fit only; saved pieces already cover it")

    guard outcomes != nil, let next = artifact.nextCheckpoint else {
      // Finished.
      switch leading?.grade {
      case .s?, .a?:
        let replace = leading!.drops(leading!.profile.score(artifact.substats)).map {
          $0.isInfinite
            ? "no new drop beats it" : "\(ResinCost.duration(forDrops: $0)) of resin to replace"
        }
        return Verdict(
          kind: .keep, role: leading,
          reason: "\(leading!.grade!.rawValue)" + (replace.map { " · \($0)" } ?? ""))
      case _ where gap != nil:
        return Verdict(kind: .keep, role: gap, reason: mainFit(gap!))
      default:
        // B for a damage role, or A or B for a support: kept while it ranks among saved pieces.
        let candidates: [RoleContext] = [leading, support].compactMap { $0 }
        let middle = candidates.first { (role: RoleContext) -> Bool in
          role.grade == .b || (role.isSupport && role.grade == .a)
        }
        if let role = middle {
          let label = role.grade!.rawValue + (role.isSupport ? " for a support" : "")
          if role.saved.isEmpty {
            return Verdict(
              kind: .review, role: role,
              reason: "\(label) · no saved +20 \(role.kind) to compare yet")
          }
          let score = role.profile.score(artifact.substats)
          return Verdict(kind: .keep, role: role, reason: label + " · " + role.rank(score))
        }
        if let thin {
          return Verdict(
            kind: .review, role: thin, reason: "C · only \(thin.saved.count) saved \(thin.kind)")
        }
        return fodder
      }
    }
    switch leading?.grade {
    case .s?:
      return Verdict(
        kind: .level, targetLevel: 20, role: leading, reason: "S · could be one of your best")
    case .a?:
      return Verdict(kind: .level, targetLevel: next, role: leading, reason: "A · worth rolling")
    case _ where gap != nil:
      return Verdict(kind: .level, targetLevel: next, role: gap, reason: mainFit(gap!))
    case .b?:
      return Verdict(
        kind: .level, targetLevel: next, role: leading, reason: "B · look again at +\(next)")
    default:
      if let thin {
        return Verdict(
          kind: .level, targetLevel: next, role: thin,
          reason: "C · only \(thin.saved.count) saved \(thin.kind)")
      }
      if let support {
        return Verdict(
          kind: .fodder, role: support,
          reason: "\(support.grade!.rawValue) for a support; supports level only at S")
      }
      return fodder
    }
  }
}

extension VerdictEngine {
  /// Four-star pieces are judged by set and main stat: guides pick them for a support set such as
  /// Instructor or The Exile, and their substats rarely decide the choice. Matches already require
  /// a character whose build lists the set.
  static func fourStar(
    _ artifact: Artifact, matches: [CharacterMatch], inventory: [Artifact], excluding: UUID?,
    policy: VerdictPolicy, standings: inout [String: RoleStanding]
  ) -> Verdict {
    let kind = "\(artifact.setName) \(artifact.main.label) \(artifact.slot.plural)"
    guard
      let lead = matches.max(by: {
        ($0.setFit == .preferred ? 1 : 0, $0.role.isReviewed ? 1 : 0)
          < ($1.setFit == .preferred ? 1 : 0, $1.role.isReviewed ? 1 : 0)
      })
    else {
      let used = CharacterRoles.all.contains { role in
        role.sets.contains { Artifact.normalizeSet($0.name) == artifact.setKey }
      }
      return Verdict(
        kind: .fodder, match: nil,
        reason: used
          ? "Four-star; no \(artifact.setName) user takes \(artifact.main.label) \(artifact.slot.plural)"
          : "Four-star \(artifact.setName) is an early-game set")
    }
    let saved = inventory.filter {
      $0.rarity == 4 && $0.id != (excluding ?? artifact.id) && $0.setKey == artifact.setKey
        && $0.slot == artifact.slot && $0.main == artifact.main
    }
    if saved.count < policy.fourStarCopies {
      let reason = "Four-star \(artifact.setName) · \(saved.count) saved like it"
      return artifact.isFinished
        ? Verdict(kind: .keep, match: lead, reason: reason)
        : Verdict(kind: .level, targetLevel: artifact.maxLevel, match: lead, reason: reason)
    }
    // Enough copies: only more useful lines than a saved copy, for any eligible character, make
    // it worth a look.
    func lines(_ piece: Artifact, _ match: CharacterMatch) -> Int {
      let useful = Set(match.usefulStats + match.secondaryStats)
      return (piece.substats + (piece.unactivated.map { [$0] } ?? [])).filter {
        useful.contains($0.key)
      }.count
    }
    let wanting = matches.filter { match in
      lines(artifact, match) > saved.map { lines($0, match) }.min() ?? .max
    }
    for match in matches where !wanting.contains(where: { $0.roleID == match.roleID }) {
      standings[match.roleID] = .covered(saved.count)
    }
    if let better = wanting.first {
      return Verdict(
        kind: .review, match: better, reason: "More useful lines than a saved \(kind) piece")
    }
    return Verdict(kind: .fodder, match: lead, reason: "Enough saved \(kind)")
  }
}

/// Per-role inputs: profile, grade, rarity table, replacement odds, and the saved pool's scores.
struct RoleContext {
  let match: CharacterMatch
  let profile: Profile
  let grade: ArtifactTier?
  /// Nil when no core substat can appear on this piece; the role then fits by main stat only.
  let rarity: DropRarity?
  /// An on-set role needs this set; an off-piece role accepts the slot and main from any set.
  let setChance: Double
  /// Saved +20 scores of the same slot and main stat that the role would wear instead, highest
  /// first: this set's for an on-set role, every set's for an off-piece.
  let saved: [Int]
  /// What those saved pieces are, for reasons: "Obsidian Codex HP flowers" or "HP flowers".
  let kind: String
  /// Saved pieces this role's stat-profile group can use at once, capped by the policy.
  let backups: Int
  let wearRank: Int
  let rareOffPiece: Bool

  init(
    _ match: CharacterMatch, artifact: Artifact, saved: [Artifact], matches: [CharacterMatch],
    policy: VerdictPolicy
  ) {
    self.match = match
    profile = match.profile
    grade = match.grades?.grade
    rarity =
      match.usefulStats.contains { $0 != artifact.main }
      ? RarityCache.shared.rarity(artifact.slot, artifact.main, match.profile) : nil
    setChance = match.setFit == .offPiece ? 1 : 0.5
    let onSet = match.scope == .sameSet
    self.saved = saved.filter { !onSet || $0.setKey == artifact.setKey }
      .map { match.profile.score($0.substats) }.sorted(by: >)
    kind =
      (onSet ? "\(artifact.setName) " : "") + "\(artifact.main.label) \(artifact.slot.plural)"
    // Roles that run this set share its saved pieces; an off-piece shares every set's.
    let group = matches.filter {
      $0.profile.weights == match.profile.weights && (!onSet || $0.scope == .sameSet)
    }.count
    backups = min(max(1, group), policy.maxBackups)
    wearRank = match.wearRank(artifact.slot)
    rareOffPiece = match.isRareOffPiece(artifact.slot)
  }

  /// Set aside when the slot is a rare off-piece or enough saved pieces beat `best`.
  func standing(best: Int) -> RoleStanding {
    if rareOffPiece { return .rareOffPiece }
    let beaten = saved.filter { $0 > best }.count
    return beaten < backups ? .open : .covered(beaten)
  }

  var tierRank: Int { grade.flatMap { ArtifactTier.allCases.firstIndex(of: $0) } ?? .max }

  /// A role without both crit stats: a healer, shield, buffer, Energy or reaction support.
  var isSupport: Bool {
    !(match.usefulStats.contains(.critRate) && match.usefulStats.contains(.critDamage))
  }

  func drops(_ score: Int) -> Double? {
    guard let rarity else { return nil }
    return rarity.expectedDropsToBeat(score, setChance: setChance) ?? .infinity
  }

  /// Where a finished score sits among the saved pieces.
  func rank(_ score: Int) -> String {
    let better = saved.filter { $0 > score }.count
    if better > 0 { return "#\(better + 1) of saved \(kind)" }
    return saved.contains(score)
      ? "tied for best of \(saved.count) saved \(kind)"
      : "beats all \(saved.count) saved \(kind)"
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
