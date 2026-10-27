import LoupeCore
import SwiftUI

/// Shared visual tokens. Tier colors follow Genshin's rarity palette so S reads as gold.
enum Theme {
  static let accent = Color(red: 0.49, green: 0.86, blue: 0.77)
  static let attention = Color(red: 1.0, green: 0.66, blue: 0.3)
  static let hud = Color(red: 0.055, green: 0.068, blue: 0.09)
  static let surface = Color.white.opacity(0.045)
  static let surfaceStrong = Color.white.opacity(0.08)
  static let hairline = Color.white.opacity(0.09)

  static func verdict(_ kind: VerdictKind) -> Color {
    switch kind {
    case .keep: Color(red: 0.42, green: 0.85, blue: 0.55)
    case .level: Color(red: 0.45, green: 0.68, blue: 1.0)
    case .review: attention
    case .fodder: Color(white: 0.6)
    }
  }

  static func tier(_ tier: ArtifactTier?) -> Color {
    switch tier {
    case .s: Color(red: 1.0, green: 0.78, blue: 0.36)
    case .a: Color(red: 0.74, green: 0.58, blue: 1.0)
    case .b: Color(red: 0.45, green: 0.68, blue: 1.0)
    case .c: Color(red: 0.52, green: 0.8, blue: 0.58)
    case .d: Color(white: 0.62)
    case nil: Color(white: 0.55)
    }
  }
}

func score(_ value: Double, digits: Int = 1) -> String {
  value.formatted(.number.precision(.fractionLength(digits)))
}

/// Rarity of the headline score among new drops of the same slot and main stat, and the expected
/// days of domain resin before a better one. Unfinished pieces describe their median projection.
func rarityLine(_ grades: CharacterGradeSummary?, artifact: Artifact, compact: Bool = false)
  -> String?
{
  guard let share = grades?.rarityShare else { return nil }
  let kind = "new \(artifact.main.label) \(artifact.slot.plural)"
  let standing = share <= 0.5 ? "top \(percent(share)) of \(kind)" : "bottom half of \(kind)"
  let replacement =
    grades?.replacementDrops.map {
      let cost = "\(ResinCost.duration(forDrops: $0)) of resin to beat"
      return compact ? cost : cost + " (~\(roughCount(ResinCost.resin(forDrops: $0))) resin)"
    } ?? "no new drop beats it"
  let headline =
    artifact.level == 20
    ? standing.prefix(1).uppercased() + standing.dropFirst()
    : "Median +20: " + standing
  return headline + " · " + replacement
}

/// The assumptions and counts behind `rarityLine`'s resin estimate.
func rarityHelp(_ grades: CharacterGradeSummary?) -> String? {
  grades?.replacementDrops.map {
    ResinCost.breakdown(forDrops: $0)
      + ". Assumes top-level domain runs of this set: ~1.07 five-stars per 20 resin, 180 resin a day."
  }
}

/// Which grade the headline shows: the roll grade, from the expected +20 score before +20 and
/// the final score at +20.
struct GradeHeadline {
  enum Kind { case graded, ungraded, mainStatFit, specialRolls, needsReread, noMatch, fourStar }
  let kind: Kind
  let tier: ArtifactTier?
  let finished: Bool

  init(match: CharacterMatch?, artifact: Artifact) {
    finished = artifact.isFinished
    guard artifact.rarity == 5 else {
      (kind, tier) = (.fourStar, nil)
      return
    }
    guard let match else {
      (kind, tier) = (.noMatch, nil)
      return
    }
    if let grade = match.grades?.grade {
      (kind, tier) = (.graded, grade)
    } else if match.potential == nil,
      !match.usefulStats.contains(where: { $0 != artifact.main })
    {
      (kind, tier) = (.mainStatFit, nil)
    } else if match.potential == nil, artifact.rule != .ordinary {
      (kind, tier) = (.specialRolls, nil)
    } else if match.potential == nil {
      (kind, tier) = (.needsReread, nil)
    } else {
      (kind, tier) = (.ungraded, nil)
    }
  }

  /// Short form for list rows where the full caption would truncate.
  var shortCaption: String {
    switch kind {
    case .graded: finished ? "Final (experimental)" : "Roll grade (experimental)"
    case .ungraded: "Ungraded"
    case .mainStatFit: "Main-stat fit"
    case .specialRolls: "Special rolls"
    case .needsReread: "Needs full read"
    case .noMatch: "No match"
    case .fourStar: "Four-star"
    }
  }

  var caption: String {
    switch kind {
    case .graded: finished ? "Final grade · experimental" : "Roll grade · experimental"
    case .ungraded: "Ungraded · not a D"
    case .mainStatFit: "Main-stat fit · no core substats"
    case .specialRolls: "Special rolls · no ordinary odds"
    case .needsReread: "Forecast needs a full read"
    case .noMatch: "No character match"
    case .fourStar: "Four-star · set and main stat only"
    }
  }
}

struct GradeBadge: View {
  let tier: ArtifactTier?
  var size: CGFloat = 44
  var placeholder = "–"

  var body: some View {
    let color = Theme.tier(tier)
    ZStack {
      RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        .fill(tier == nil ? Color.clear : color.opacity(0.16))
      RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        .strokeBorder(
          color.opacity(tier == nil ? 0.45 : 0.75),
          style: StrokeStyle(lineWidth: size > 30 ? 1.5 : 1, dash: tier == nil ? [3, 3] : []))
      Text(tier?.rawValue ?? placeholder)
        .font(.system(size: size * 0.54, weight: .heavy, design: .rounded))
        .foregroundStyle(tier == nil ? Color.secondary : color)
    }
    .frame(width: size, height: size)
    .accessibilityElement()
    .accessibilityLabel(tier.map { "Tier \($0.rawValue), experimental" } ?? "Ungraded")
  }
}

/// A small tier label used inside outcome tiles and lists.
struct TierChip: View {
  let tier: ArtifactTier?
  var body: some View {
    Text(tier?.rawValue ?? "–")
      .font(.system(size: 10, weight: .bold, design: .rounded))
      .foregroundStyle(tier == nil ? Color.secondary : Theme.tier(tier))
      .frame(minWidth: 16, minHeight: 15)
      .background(
        Theme.tier(tier).opacity(tier == nil ? 0.08 : 0.18),
        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
  }
}

/// The at-a-glance answer for the current piece: what to do with it, and the main reason.
struct VerdictBanner: View {
  let verdict: Verdict
  /// Smaller type for the overlay.
  var compact = false
  var lines = 2
  /// The character and role shown beside the banner. The name is omitted only when that role is
  /// the verdict's.
  var displayedCharacterID: String?
  var displayedRoleID: String?

  var body: some View {
    HStack(spacing: 8) {
      Text(verdict.title.uppercased())
        .font(.system(size: compact ? 11 : 13, weight: .heavy)).lineLimit(1).fixedSize()
        .foregroundStyle(Theme.hud)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.verdict(verdict.kind), in: Capsule())
      Text(
        Self.text(
          verdict, lines: lines, displayedCharacterID: displayedCharacterID,
          displayedRoleID: displayedRoleID)
      )
      .font(compact ? .caption2 : .callout).foregroundStyle(.secondary)
      .lineLimit(lines).minimumScaleFactor(0.85)
      .fixedSize(horizontal: false, vertical: lines > 1)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      "\(verdict.title). "
        + Self.text(
          verdict, lines: 2, displayedCharacterID: displayedCharacterID,
          displayedRoleID: displayedRoleID)
    )
    .help("Advice only. Rules and defaults: docs/grading-approach.md")
  }

  /// One line sits just above the displayed role, so it drops the name only when that role is
  /// the verdict's. Another role of the same character names the verdict's role.
  static func text(
    _ verdict: Verdict, lines: Int, displayedCharacterID: String?, displayedRoleID: String? = nil
  ) -> String {
    let sameRole =
      displayedRoleID.map { $0 == verdict.roleID } ?? (displayedCharacterID == verdict.characterID)
    if sameRole { return lines == 1 ? verdict.reason : verdict.summary }
    if displayedCharacterID == verdict.characterID, let name = verdict.characterName,
      let role = verdict.roleName
    {
      return "\(name), \(role) · \(verdict.reason)"
    }
    return verdict.summary
  }
}

struct Chip: View {
  let text: String
  var systemImage: String?
  var tint: Color = .secondary

  var body: some View {
    HStack(spacing: 3) {
      if let systemImage { Image(systemName: systemImage).imageScale(.small) }
      Text(text).lineLimit(1)
    }
    .font(.system(size: 10, weight: .medium))
    .foregroundStyle(tint)
    .padding(.horizontal, 6).padding(.vertical, 2)
    .background(Theme.surfaceStrong, in: Capsule())
  }
}

extension CharacterSetFit {
  var shortLabel: String {
    switch self {
    case .preferred: "Preferred set"
    case .alternative: "Alt set"
    case .offPiece: "Off-piece"
    }
  }
}

/// A potential user's row label: its set fit, or why the verdict set the role aside.
struct RoleRowStatus {
  let label: String
  let help: String?
  let setAside: Bool

  init(_ match: CharacterMatch, standing: RoleStanding, artifact: Artifact) {
    switch standing {
    case .open:
      (label, help, setAside) = (match.setFit.shortLabel, nil, false)
    case .covered(let count):
      let pool = match.scope == .sameSet ? "\(artifact.setName) " : ""
      (label, help, setAside) = (
        "Covered",
        "\(count) saved \(pool)\(artifact.main.label) \(artifact.slot.plural) already cover "
          + "this role.", true
      )
    case .rareOffPiece:
      (label, help, setAside) = (
        match.setFit.shortLabel,
        "A 4+1 build rarely wears its off-set piece in the \(artifact.slot.rawValue) slot.", true
      )
    }
  }

  /// The potential-users caption: grades rank the list, and they are rarity, not damage.
  static let orderCaption = "By grade, not damage"
  static let orderHelp =
    "Open roles first, then by roll grade, then on-set before off-piece. Dimmed roles are set "
    + "aside: enough saved pieces they would wear beat this one, or it is an off-set flower or "
    + "plume. "
}

/// Median, P90, and best-possible +20 outcomes for one stated role or profile.
struct OutcomeLadder: View {
  let result: Potential
  let grades: CharacterGradeSummary?
  var digits = 1
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 6 : 8) {
      tile("Median", result.summary.p50Score, grades?.rarityShare, emphasized: true)
      tile("P90", result.summary.p90Score, grades?.p90Share)
      tile("Best possible", result.maximumScore, grades?.bestShare, ceiling: true)
    }
  }

  private func tile(
    _ title: String, _ value: Double, _ share: Double?, emphasized: Bool = false,
    ceiling: Bool = false
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(title.uppercased())
        .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(.secondary)
        .lineLimit(1).minimumScaleFactor(0.8)
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(score(value, digits: digits))
          .font(
            .system(
              size: compact ? 16 : 20, weight: emphasized ? .bold : .semibold, design: .rounded)
          )
          .monospacedDigit()
          .foregroundStyle(ceiling ? Color.secondary : .primary)
        if let share {
          Text(share <= 0.5 ? "top \(percent(share))" : "bottom half")
            .font(.system(size: compact ? 9 : 10)).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.7)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, compact ? 7 : 10).padding(.vertical, compact ? 5 : 8)
    .background(
      emphasized ? Theme.surfaceStrong : Theme.surface,
      in: RoundedRectangle(cornerRadius: 7, style: .continuous)
    )
    .overlay {
      if ceiling {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
      }
    }
    .help(
      ceiling
        ? "Best possible is a ceiling, not a likely result."
        : "Smallest +20 score whose cumulative probability reaches \(title == "P90" ? 90 : 50)%.")
  }
}

/// Saved-inventory comparison. Scope and saved count are always visible with every claim.
struct AccountBlock: View {
  let result: Potential
  let scope: ComparisonScope
  let finished: Bool
  var compact = false

  var body: some View {
    VStack(alignment: .leading, spacing: compact ? 3 : 5) {
      HStack(spacing: 5) {
        Text("SAVED ACCOUNT").font(.system(size: 8.5, weight: .semibold))
          .foregroundStyle(.secondary)
        Chip(text: scope == .offPiece ? "All sets" : "Same set")
        Chip(text: "n=\(result.comparisonCount) saved +20")
        Chip(text: "partial")
      }
      if result.chanceToBeatBest == nil {
        Text("No comparable +20 saved yet. Intrinsic assessment still applies.")
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        if let chance = result.chanceToBeatBest {
          row(
            "Strictly beat best",
            finished ? (chance == 1 ? "Yes" : "No") : percent(chance), strong: true)
        }
        if finished {
          if let rank = result.bestRank { row("Rank (ties share)", "#\(rank)") }
        } else {
          if let top = result.rankChances.first(where: { $0.rank == 3 }) {
            row("Top 3 or tied", percent(top.probability))
          }
          if let rank = result.bestRank { row("Best reachable rank", "#\(rank)") }
        }
        if result.comparisonCount < 3 {
          Text("Top-three needs 3 saved comparables.").font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  private func row(_ title: String, _ value: String, strong: Bool = false) -> some View {
    HStack {
      Text(title).foregroundStyle(strong ? .primary : .secondary)
      Spacer()
      Text(value).monospacedDigit().fontWeight(strong ? .bold : .medium)
        .foregroundStyle(strong ? Theme.accent : .primary)
    }
    .font(compact ? .caption : .callout)
  }
}

/// A titled group for the dashboard sidebar and main column.
struct Panel<Content: View>: View {
  let title: String
  var systemImage: String?
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 6) {
        if let systemImage {
          Image(systemName: systemImage).foregroundStyle(Theme.accent).imageScale(.small)
        }
        Text(title.uppercased()).font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary).kerning(0.6)
      }
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

struct StatusDot: View {
  let verified: Bool
  var active = true
  var body: some View {
    Circle()
      .fill(!active ? Color.secondary : verified ? Theme.accent : Theme.attention)
      .frame(width: 7, height: 7)
      .shadow(color: verified && active ? Theme.accent.opacity(0.6) : .clear, radius: 3)
  }
}
