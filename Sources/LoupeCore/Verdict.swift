import Foundation

public enum VerdictKind: String, Sendable, CaseIterable {
  case keep, level, review, fodder
}

/// Whether a role still has a use for the piece.
public enum RoleStanding: Sendable, Equatable {
  case open
  /// This many saved pieces the role would wear instead already beat the piece's best outcome.
  /// The role can still keep the piece as a spare when it grades it S, or A for a damage role.
  case covered(Int)
  /// An off-set flower or plume graded below this letter, the lowest that counts for that slot
  /// (`VerdictPolicy`): a 4+1 build rarely wears its off-piece there, so the role cannot keep or
  /// level the piece.
  case offSetBelowBar(ArtifactTier)
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
  /// The lowest grade at which an off-set flower or plume counts for a role, unfinished and
  /// finished. A 4+1 build rarely wears its off-piece in those slots, so by default only S
  /// counts: it levels an unfinished one to +20 and keeps a finished one. About half of finished
  /// flowers grade A for some archetype of some set, so a finished bar at A keeps half of them.
  public var offSetUnfinishedBar = ArtifactTier.s
  public var offSetFinishedBar = ArtifactTier.s

  public init() {}
  public static let standard = VerdictPolicy()
}

/// Verdicts follow the best roll grade among the piece's roles (`RollGrade`). A main-stat-only
/// fit whose saved pool has room ranks below S and A and above B.
/// - Unfinished: S levels to +20. A and B level to the next checkpoint, where the grade is read
///   again, so EXP follows the rolls. C and D are fodder unless the saved pool is thin but not
///   empty. Main-stat-only fits level while the pool has room. Supports, roles without both crit
///   stats, mostly need their main stat, and a flower suits nearly every support, so a support's
///   grade levels a flower or plume only at S. A support's A or B levels a sands, goblet or
///   circlet one checkpoint while few of that main stat are saved, like a main-stat-only fit.
/// - Finished: S and A are kept. B, or A or B for a support, is kept while it ranks among the
///   saved pieces a role can use and reviewed when nothing is saved. C is reviewed only when that
///   pool is thin but not empty, and D is fodder.
/// A role is covered when enough saved +20 pieces of the same slot and main stat already beat the
/// piece's best outcome for it. An on-set role counts only saved pieces of this set, which are
/// what it would wear instead; an off-piece role counts every set. Covered roles do not decide
/// the verdict, but saved pieces never make a good piece fodder: when the rest would make it
/// fodder and a covered role grades it S, or A for a damage role, it is kept as a spare, finished
/// or not. A covered B can still end as fodder.
/// A 4+1 build rarely takes its off-piece in the flower or plume slot, so an off-set flower or
/// plume counts for a role only at a higher grade, `VerdictPolicy.offSetUnfinishedBar` and
/// `offSetFinishedBar`. Below it the role cannot level, keep or rescue the piece.
public enum VerdictEngine {
  /// Decides from the artifact's character matches and the saved +20 inventory.
  /// `excluding` removes the saved record of this same piece from comparisons. `outcomes` is an
  /// enumeration the caller already holds; one for another artifact is ignored.
  public static func evaluate(
    _ artifact: Artifact, matches: [CharacterMatch], inventory: [Artifact],
    excluding: UUID? = nil, policy: VerdictPolicy = .standard, outcomes: RollOutcomes? = nil
  ) -> Verdict {
    var standings: [String: RoleStanding] = [:]
    var verdict =
      artifact.rarity == 4
      ? fourStar(
        artifact, matches: matches, inventory: inventory, excluding: excluding, policy: policy,
        standings: &standings)
      : ordinary(
        artifact, matches: matches, inventory: inventory, excluding: excluding, policy: policy,
        outcomes: outcomes, standings: &standings)
    verdict.standings = standings
    return verdict
  }

  private static func ordinary(
    _ artifact: Artifact, matches: [CharacterMatch], inventory: [Artifact], excluding: UUID?,
    policy: VerdictPolicy, outcomes: RollOutcomes?, standings: inout [String: RoleStanding]
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
    // An off-set flower or plume below its bar is set aside even without a forecast.
    for role in roles where !role.clearsOffSetBar {
      standings[role.match.roleID] = .offSetBelowBar(role.offSetBar!)
    }
    let outcomes =
      artifact.level == 20
      ? nil
      : outcomes.flatMap { $0.artifact == artifact ? $0 : nil } ?? (try? RollOutcomes(artifact))
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
    let verdict = uncovered(
      artifact, roles: roles, standings: standings, finished: outcomes == nil,
      strongest: strongest)
    guard verdict.kind == .fodder else { return verdict }
    // Saved pieces never make a good piece fodder: a covered role's S, or a damage role's A, keeps
    // it as a spare. Leveling it cannot beat the saved pieces, so an unfinished spare stays put.
    let spare = strongest(
      roles.filter {
        if case .covered = standings[$0.match.roleID] {
          $0.grade == .s || ($0.grade == .a && !$0.isSupport)
        } else {
          false
        }
      })
    guard let spare, case .covered(let beaten)? = standings[spare.match.roleID] else {
      return verdict
    }
    let beat =
      outcomes == nil
      ? (beaten == 1 ? "scores higher" : "score higher")
      : (beaten == 1 ? "beats its best outcome" : "beat its best outcome")
    return Verdict(
      kind: .keep, role: spare,
      reason: spare.label + " · spare; \(spare.count(beaten)) \(beat)")
  }

  /// The verdict from the roles no saved pieces cover.
  private static func uncovered(
    _ artifact: Artifact, roles: [RoleContext], standings: [String: RoleStanding],
    finished: Bool, strongest: ([RoleContext]) -> RoleContext?
  ) -> Verdict {
    let kind = "\(artifact.main.label) \(artifact.slot.plural)"
    let left = roles.filter {
      if case .covered = standings[$0.match.roleID] { false } else { true }
    }
    guard !left.isEmpty else {
      let pool = roles.allSatisfy { $0.match.scope == .sameSet } ? roles[0].kind : kind
      let beaten = finished ? "beat it" : "beat its best outcome"
      return Verdict(kind: .fodder, reason: "Enough saved \(pool) \(beaten) for every role")
    }
    // Off-set flowers and plumes below their bar count for nothing.
    let open = left.filter(\.clearsOffSetBar)
    let flowerOrPlume = artifact.slot == .flower || artifact.slot == .plume
    // A support's grade counts only at S; below that it can still keep a finished piece that
    // ranks among the saved ones, or level a sands, goblet or circlet while few are saved.
    let leading = strongest(open.filter { !$0.isSupport || $0.grade == .s })
    let support = strongest(open.filter(\.isSupport)).flatMap {
      $0.tierRank < (leading?.tierRank ?? .max) ? $0 : nil
    }
    let gap = open.filter { $0.grade == nil && $0.saved.count < $0.backups }.max {
      $0.wearRank < $1.wearRank
    }
    let roomForSupport =
      flowerOrPlume
      ? nil
      : strongest(
        open.filter {
          $0.isSupport && ($0.grade == .a || $0.grade == .b) && $0.saved.count < $0.backups
        })
    // Any C role whose saved pool is thin can rescue the piece; supports only once it is
    // finished, since their grade levels only at S. An empty pool usually means the bag was not
    // scanned, so it does not make a C piece worth it.
    let thin = strongest(
      open.filter {
        $0.grade == .c && !$0.saved.isEmpty && $0.saved.count < $0.backups
          && (finished || !$0.isSupport)
      })
    let mainFit = { (role: RoleContext) in
      "Main stat fills a gap: \(role.count(role.saved.count))"
    }
    // Fodder names the best letter that says something about the piece and why it does not
    // count. An off-set support's letter says little: any flower with its one stat earns it. When
    // such a role grades higher than the named one, the reason says whom its letter covers.
    let fodder: Verdict = {
      let best = strongest(left.filter { $0.clearsOffSetBar || !$0.isSupport })
      let covered = roles.filter { role in !left.contains { $0.match.roleID == role.match.roleID } }
      if let top = strongest(covered), top.tierRank < best?.tierRank ?? .max,
        case .covered(let beaten)? = standings[top.match.roleID]
      {
        let beat = beaten == 1 ? "beats" : "beat"
        return Verdict(
          kind: .fodder, role: top,
          reason:
            "\(top.label) · \(top.count(beaten)) \(beat) \(finished ? "it" : "its best outcome")")
      }
      guard let best else {
        return Verdict(
          kind: .fodder,
          reason: open.isEmpty
            ? "Off-set \(artifact.slot.plural) count only at \(left[0].offSetBar!.atOrAbove)"
            : "Main-stat fit only; saved pieces already cover it")
      }
      let grade = best.grade!.rawValue
      let higher = left.first { !$0.clearsOffSetBar && $0.tierRank < best.tierRank }
      let whom =
        higher.map {
          "on-set and damage roles; off-set \(artifact.slot.plural) need "
            + $0.offSetBar!.atOrAbove
        } ?? "every role"
      let reason: String
      switch best.grade! {
      case .c: reason = "C at best for \(whom)"
      case .d: reason = "D for \(whom)"
      case _ where !best.clearsOffSetBar:
        reason =
          "\(grade) as an off-set \(artifact.slot.rawValue); needs \(best.offSetBar!.atOrAbove)"
      case _ where flowerOrPlume:
        reason = "\(grade) for a support; supports level \(artifact.slot.plural) only at S"
      default:
        reason =
          "\(grade) for a support; \(best.count(best.saved.count)) \(best.saved.count == 1 ? "is" : "are") enough"
      }
      return Verdict(kind: .fodder, role: best, reason: reason)
    }()

    guard !finished, let next = artifact.nextCheckpoint else {
      switch leading?.grade {
      case .s?, .a?:
        let replace = leading!.drops(leading!.profile.score(artifact.substats)).map {
          $0.isInfinite
            ? "no new drop beats it" : "\(ResinCost.duration(forDrops: $0)) of resin to replace"
        }
        return Verdict(
          kind: .keep, role: leading,
          reason: leading!.label + (replace.map { " · \($0)" } ?? ""))
      case _ where gap != nil:
        return Verdict(kind: .keep, role: gap, reason: mainFit(gap!))
      default:
        // B for a damage role, or A or B for a support: kept while it ranks among saved pieces.
        let candidates: [RoleContext] = [leading, support].compactMap { $0 }
        let middle = candidates.first { (role: RoleContext) -> Bool in
          role.grade == .b || (role.isSupport && role.grade == .a)
        }
        if let role = middle {
          let label = role.label + (role.isSupport ? " for a support" : "")
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
            kind: .review, role: thin, reason: "C · only \(thin.count(thin.saved.count))")
        }
        return fodder
      }
    }
    let forSupport = { (role: RoleContext) in
      Verdict(
        kind: .level, targetLevel: next, role: role,
        reason: "\(role.label) for a support · \(role.count(role.saved.count))")
    }
    // S, then A, then a main-stat gap, then B. A damage role's letter leads a support's.
    switch leading?.grade {
    case .s?:
      return Verdict(
        kind: .level, targetLevel: 20, role: leading,
        reason: "\(leading!.label) · could be one of your best")
    case .a?:
      return Verdict(
        kind: .level, targetLevel: next, role: leading, reason: "\(leading!.label) · worth rolling")
    case _ where roomForSupport?.grade == .a:
      return forSupport(roomForSupport!)
    case _ where gap != nil:
      return Verdict(kind: .level, targetLevel: next, role: gap, reason: mainFit(gap!))
    case .b?:
      return Verdict(
        kind: .level, targetLevel: next, role: leading,
        reason: "\(leading!.label) · look again at +\(next)")
    case _ where roomForSupport != nil:
      return forSupport(roomForSupport!)
    default:
      if let thin {
        return Verdict(
          kind: .level, targetLevel: next, role: thin,
          reason: "C · only \(thin.count(thin.saved.count))")
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
  /// One of them: "Obsidian Codex HP flower".
  let single: String
  /// Saved pieces this role's stat-profile group can use at once, capped by the policy.
  let backups: Int
  let wearRank: Int
  let rareOffPiece: Bool
  /// For an off-set flower or plume, the lowest grade that counts for this role.
  let offSetBar: ArtifactTier?

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
    let prefix = (onSet ? "\(artifact.setName) " : "") + "\(artifact.main.label) "
    kind = prefix + artifact.slot.plural
    single = prefix + artifact.slot.rawValue
    // Roles that run this set share its saved pieces; an off-piece shares every set's.
    let group = matches.filter {
      $0.profile.weights == match.profile.weights && (!onSet || $0.scope == .sameSet)
    }.count
    // At least one, so a role with nothing saved is never covered.
    backups = max(1, min(group, policy.maxBackups))
    wearRank = match.wearRank(artifact.slot)
    rareOffPiece = match.isRareOffPiece(artifact.slot)
    offSetBar =
      rareOffPiece
      ? (artifact.isFinished ? policy.offSetFinishedBar : policy.offSetUnfinishedBar) : nil
  }

  /// Set aside when an off-set flower or plume is below its bar or enough saved pieces beat
  /// `best`.
  func standing(best: Int) -> RoleStanding {
    if let offSetBar, !clearsOffSetBar { return .offSetBelowBar(offSetBar) }
    let beaten = saved.filter { $0 > best }.count
    return beaten < backups ? .open : .covered(beaten)
  }

  var tierRank: Int { grade.flatMap { ArtifactTier.allCases.firstIndex(of: $0) } ?? .max }

  /// False for an off-set flower or plume graded below its bar, or not graded at all.
  var clearsOffSetBar: Bool {
    guard let offSetBar else { return true }
    return tierRank <= ArtifactTier.allCases.firstIndex(of: offSetBar)!
  }

  /// The grade for reasons, marked when the piece would be this role's off-set flower or plume.
  var label: String { (grade?.rawValue ?? "") + (rareOffPiece ? " off-set" : "") }

  /// "1 saved HP flower", "0 saved HP flowers".
  func count(_ count: Int) -> String { "\(count) saved \(count == 1 ? single : kind)" }

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
    if saved.count == 1 {
      return saved[0] == score ? "tied with the 1 saved \(single)" : "beats the 1 saved \(single)"
    }
    return saved.contains(score)
      ? "tied for best of \(saved.count) saved \(kind)"
      : "beats all \(saved.count) saved \(kind)"
  }
}

extension ArtifactTier {
  /// "S", or "A or better", for the lowest grade that counts.
  public var atOrAbove: String { self == .s ? "S" : "\(rawValue) or better" }
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
