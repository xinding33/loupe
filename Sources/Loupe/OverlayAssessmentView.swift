import LoupeCore
import SwiftUI

enum AccountSummary {
  static func label(_ result: Potential, scope: ComparisonScope, finished: Bool) -> String {
    let scopeLabel = scope == .offPiece ? "all sets" : "same set"
    guard let chance = result.chanceToBeatBest else { return "No +20 baseline (\(scopeLabel))" }
    let value = finished ? (chance == 1 ? "Yes" : "No") : percent(chance)
    return "Beat saved best: \(value) (\(scopeLabel), n=\(result.comparisonCount))"
  }
}

/// Click-through result surface. The interactive strip lives in a separate panel above it.
struct OverlayView: View {
  @ObservedObject var model: Model

  private var expanded: Bool { model.overlayExpanded }

  var body: some View {
    VStack(alignment: .leading, spacing: expanded ? 10 : 7) {
      statusRow
      if let artifact = model.current {
        if model.assessmentMode == .characters, let verdict = model.verdict {
          VerdictBanner(
            verdict: verdict, compact: true, lines: expanded ? 2 : 1,
            displayedCharacterID: model.selectedMatch?.characterID,
            displayedRoleID: model.selectedMatch?.roleID)
        }
        hero(artifact)
        if expanded {
          details(artifact)
        } else {
          accountLine(artifact)
        }
      } else {
        Text(model.status).font(.caption).foregroundStyle(.secondary)
          .lineLimit(expanded ? 5 : 2).fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
    .frame(maxWidth: .infinity, alignment: .topLeading)
    .background(
      Theme.hud.opacity(0.94),
      in: UnevenRoundedRectangle(
        bottomLeadingRadius: 12, bottomTrailingRadius: 12, style: .continuous)
    )
    .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .environment(\.colorScheme, .dark)
  }

  private var statusRow: some View {
    HStack(spacing: 6) {
      StatusDot(verified: model.stability.isVerified, active: model.current != nil)
      Text(
        model.current.map { "\($0.slot.label) · \($0.main.label) · +\($0.level)" }
          ?? "Waiting for an Inventory card"
      )
      .font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
      Spacer(minLength: 4)
      if model.current != nil, !model.stability.isVerified {
        Chip(text: "Rechecking", tint: Theme.attention)
      } else if expanded, let artifact = model.current {
        Text(artifact.setName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
      }
    }
  }

  @ViewBuilder
  private func hero(_ artifact: Artifact) -> some View {
    if model.assessmentMode == .characters {
      let match = model.selectedMatch
      let headline = GradeHeadline(match: match, artifact: artifact)
      HStack(spacing: 10) {
        GradeBadge(tier: headline.tier, size: expanded ? 50 : 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(headline.caption).font(.system(size: 10, weight: .medium))
            .foregroundStyle(headline.kind == .needsReread ? Theme.attention : .secondary)
            .lineLimit(1)
          if let match {
            Text(match.characterName).font(.system(size: expanded ? 15 : 13, weight: .bold))
              .lineLimit(1)
            if expanded {
              Text(match.roleName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
          } else {
            Text("Try a manual profile").font(.system(size: 13, weight: .semibold))
          }
        }
        Spacer(minLength: 0)
      }
    } else {
      HStack(spacing: 10) {
        let result = model.potential
        Text(
          result.map { score(artifact.level == 20 ? $0.currentScore : $0.summary.p50Score) }
            ?? "–"
        )
        .font(.system(size: expanded ? 22 : 18, weight: .bold, design: .rounded)).monospacedDigit()
        .frame(minWidth: expanded ? 50 : 40, minHeight: expanded ? 50 : 40)
        .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: 10))
        VStack(alignment: .leading, spacing: 2) {
          Text(artifact.level == 20 ? "Final score" : "Median +20 score")
            .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
          Text(model.profileName).font(.system(size: 13, weight: .bold)).lineLimit(1)
          if expanded {
            Text(model.profile.explanation).font(.caption).foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 0)
      }
    }
  }

  @ViewBuilder
  private func accountLine(_ artifact: Artifact) -> some View {
    if let result = model.displayedPotential {
      Text(AccountSummary.label(result, scope: model.scope, finished: artifact.level == 20))
        .font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
        .foregroundStyle(result.comparisonCount == 0 ? Color.secondary : .primary)
    } else if model.assessmentMode == .characters,
      GradeHeadline(match: model.selectedMatch, artifact: artifact).kind == .needsReread
    {
      Text("Re-read the card; no odds are guessed.").font(.caption2)
        .foregroundStyle(Theme.attention).lineLimit(1)
    } else if let reason = unavailableReason {
      Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        .minimumScaleFactor(0.8)
    }
  }

  private var unavailableReason: String? {
    if model.assessmentMode == .profile { return model.evaluationIssue }
    return model.selectedMatch?.potentialUnavailableReason
  }

  @ViewBuilder
  private func details(_ artifact: Artifact) -> some View {
    let finished = artifact.level == 20
    let grades = model.assessmentMode == .characters ? model.selectedMatch?.grades : nil
    if let result = model.displayedPotential {
      if finished {
        Text("Final core score \(score(result.currentScore)) useful-roll points")
          .font(.caption)
      } else {
        OutcomeLadder(result: result, grades: grades, compact: true)
        HStack(spacing: 6) {
          Text("Now \(score(result.currentScore))").foregroundStyle(.secondary)
          if let chance = grades?.chanceOfAOrBetter {
            Text("·").foregroundStyle(.tertiary)
            Text("A or better \(percent(chance))")
          }
          Spacer(minLength: 0)
        }
        .font(.caption).monospacedDigit()
        Label(model.recommendation, systemImage: "arrow.up.forward.circle")
          .font(.caption.weight(.medium)).foregroundStyle(Theme.accent).lineLimit(2)
      }
      if let line = rarityLine(grades, artifact: artifact, compact: true) {
        Text(line).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
      }
      AccountBlock(result: result, scope: model.scope, finished: finished, compact: true)
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    } else {
      if let reason = unavailableReason {
        Text(reason).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      // A finished special-rule piece has a grade but no ordinary forecast.
      if let line = rarityLine(grades, artifact: artifact, compact: true) {
        Text(line).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
      }
    }
    if model.assessmentMode == .characters { users(artifact) }
    stats(artifact)
    Text("Weighted-roll screen, not damage. ER needs and Crit caps are unknown.")
      .font(.system(size: 9.5)).foregroundStyle(.tertiary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func users(_ artifact: Artifact) -> some View {
    let shortlist = model.characterShortlist
    return VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text("POTENTIAL USERS").font(.system(size: 8.5, weight: .semibold))
          .foregroundStyle(.secondary)
        Spacer()
        Text("Not damage ranking").font(.system(size: 9)).foregroundStyle(
          .tertiary)
      }
      if shortlist.allMatches.isEmpty {
        Text(CharacterRoles.noMatchDescription).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      ForEach(shortlist.visibleMatches) { match in
        let selected = model.selectedMatch?.id == match.id
        let headline = GradeHeadline(match: match, artifact: artifact)
        HStack(spacing: 6) {
          RoundedRectangle(cornerRadius: 1).fill(selected ? Theme.accent : .clear)
            .frame(width: 2, height: 12)
          Text(match.characterName).font(.caption.weight(selected ? .bold : .regular))
            .lineLimit(1)
          Spacer(minLength: 4)
          Text(match.setFit.shortLabel).font(.system(size: 9.5)).foregroundStyle(.secondary)
          TierChip(tier: headline.tier)
        }
      }
      Text(
        "\(shortlist.visibleMatches.count) of \(shortlist.allMatches.count) eligible / partial coverage. All in dashboard."
      )
      .font(.system(size: 9)).foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
      Text("Grades experimental").font(.system(size: 9)).foregroundStyle(.tertiary)
    }
  }

  private func stats(_ artifact: Artifact) -> some View {
    let lines =
      artifact.substats.map { ($0.key.label, $0.key.display($0.value), false) }
      + (artifact.unactivated.map { [("\($0.key.label) at +4", $0.key.display($0.value), true)] }
        ?? [])
    return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
      ForEach(Array(stride(from: 0, to: lines.count, by: 2)), id: \.self) { index in
        GridRow {
          ForEach(index..<min(index + 2, lines.count), id: \.self) { item in
            HStack(spacing: 4) {
              Text(lines[item].0).foregroundStyle(.secondary).lineLimit(1)
              Spacer(minLength: 2)
              Text(lines[item].1).monospacedDigit()
            }
            .opacity(lines[item].2 ? 0.6 : 1)
          }
        }
      }
    }
    .font(.caption2)
    .padding(8)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
}
