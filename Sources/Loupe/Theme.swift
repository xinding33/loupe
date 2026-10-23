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
/// on-set domain drops before a better one. Unfinished pieces describe their median projection.
func rarityLine(_ grades: CharacterGradeSummary?, artifact: Artifact, compact: Bool = false)
  -> String?
{
  guard let share = grades?.rarityShare else { return nil }
  let kind = "new \(artifact.main.label) \(artifact.slot.plural)"
  let standing = share <= 0.5 ? "top \(percent(share)) of \(kind)" : "bottom half of \(kind)"
  let replacement =
    grades?.replacementDrops.map {
      compact ? "~\(roughCount($0)) drops to beat" : "about \(roughCount($0)) domain drops to beat"
    } ?? "no new drop beats it"
  let headline =
    artifact.level == 20
    ? standing.prefix(1).uppercased() + standing.dropFirst()
    : "Median +20: " + standing
  return headline + " · " + replacement
}

/// Which grade the headline shows: the actual tier at +20, otherwise the median projection.
struct GradeHeadline {
  enum Kind { case graded, ungraded, mainStatFit, specialRolls, needsReread, noMatch }
  let kind: Kind
  let tier: ArtifactTier?
  let ceiling: ArtifactTier?
  let finished: Bool

  init(match: CharacterMatch?, artifact: Artifact) {
    finished = artifact.level == 20
    guard let match else {
      (kind, tier, ceiling) = (.noMatch, nil, nil)
      return
    }
    let grade = finished ? match.grades?.current : match.grades?.p50
    if let grade {
      kind = .graded
      tier = grade
      ceiling = finished ? nil : match.grades?.bestPossible
    } else if match.potential == nil,
      !match.usefulStats.contains(where: { $0 != artifact.main })
    {
      (kind, tier, ceiling) = (.mainStatFit, nil, nil)
    } else if match.potential == nil, artifact.rule != .ordinary {
      (kind, tier, ceiling) = (.specialRolls, nil, nil)
    } else if match.potential == nil {
      (kind, tier, ceiling) = (.needsReread, nil, nil)
    } else {
      (kind, tier, ceiling) = (.ungraded, nil, nil)
    }
  }

  /// Short form for list rows where the full caption would truncate.
  var shortCaption: String {
    switch kind {
    case .graded: finished ? "Final (experimental)" : "Median +20 (experimental)"
    case .ungraded: "Ungraded"
    case .mainStatFit: "Main-stat fit"
    case .specialRolls: "Special rolls"
    case .needsReread: "Needs full read"
    case .noMatch: "No match"
    }
  }

  var caption: String {
    switch kind {
    case .graded: finished ? "Final grade · experimental" : "Median +20 · experimental"
    case .ungraded: "Ungraded · not a D"
    case .mainStatFit: "Main-stat fit · no core substats"
    case .specialRolls: "Special rolls · no ordinary odds"
    case .needsReread: "Forecast needs a full read"
    case .noMatch: "No reviewed match"
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
  /// The character shown beside the banner. The name is omitted only when it is the verdict's.
  var displayedCharacterID: String?

  var body: some View {
    HStack(spacing: 8) {
      Text(verdict.title.uppercased())
        .font(.system(size: compact ? 11 : 13, weight: .heavy)).lineLimit(1).fixedSize()
        .foregroundStyle(Theme.hud)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Theme.verdict(verdict.kind), in: Capsule())
      Text(Self.text(verdict, lines: lines, displayedCharacterID: displayedCharacterID))
        .font(compact ? .caption2 : .callout).foregroundStyle(.secondary)
        .lineLimit(lines).minimumScaleFactor(0.85)
        .fixedSize(horizontal: false, vertical: lines > 1)
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(verdict.title). \(verdict.summary)")
    .help("Advice only. Rules and defaults: docs/grading-approach.md")
  }

  /// One line sits just above the displayed character, so it drops the name only when that
  /// character is the verdict's; otherwise the name leads.
  static func text(_ verdict: Verdict, lines: Int, displayedCharacterID: String?) -> String {
    lines == 1 && displayedCharacterID == verdict.characterID ? verdict.reason : verdict.summary
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

/// Median, P90, and best-possible +20 outcomes for one stated role or profile.
struct OutcomeLadder: View {
  let result: Potential
  let grades: CharacterGradeSummary?
  var digits = 1
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 6 : 8) {
      tile("Median", result.summary.p50Score, grades?.p50, emphasized: true)
      tile("P90", result.summary.p90Score, grades?.p90)
      tile("Best possible", result.maximumScore, grades?.bestPossible, ceiling: true)
    }
  }

  private func tile(
    _ title: String, _ value: Double, _ tier: ArtifactTier?, emphasized: Bool = false,
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
        if grades != nil { TierChip(tier: tier) }
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
