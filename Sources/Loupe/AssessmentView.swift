import LoupeCore
import SwiftUI

enum AssessmentMode: String, CaseIterable, Identifiable {
  case characters = "Character uses"
  case profile = "Manual profile"
  var id: String { rawValue }
}

enum UpgradeGuidance {
  static func checkpoint(_ artifact: Artifact) -> String {
    guard let next = artifact.nextCheckpoint else { return "Fully upgraded" }
    if let stat = artifact.unactivated {
      return "At +4: activates \(stat.key.label) \(stat.key.display(stat.value)) (fixed)"
    }
    return "Next checkpoint: +\(next)"
  }

  static func helpfulRolls(_ artifact: Artifact, usefulStats: [Stat]) -> String {
    let available = Set(
      artifact.substats.map(\.key) + (artifact.unactivated.map { [$0.key] } ?? []))
    let helpful = usefulStats.filter { available.contains($0) }
    return helpful.isEmpty
      ? "No random roll increases this core score. Utility can still matter."
      : "Helpful random rolls: " + helpful.map(\.label).joined(separator: ", ")
  }
}

extension CharacterMatch {
  var setDescription: String {
    switch setFit {
    case .preferred: "Preferred set candidate"
    case .alternative: "Alternative set candidate"
    case .offPiece: "Off-piece candidate"
    }
  }

  func headline(level: Int) -> String {
    let label = level == 20 ? "Final grade" : "Roll grade"
    return grades.map { "\(label): \($0.grade.rawValue) (experimental)" }
      ?? "Ungraded / main-stat fit"
  }
}

extension Model {
  var assessmentDescription: String {
    guard let current else { return "No artifact" }
    guard assessmentMode == .characters else { return profileName + " / " + profile.explanation }
    guard let match = selectedMatch else { return CharacterRoles.noMatchDescription }
    return
      ([
        match.characterName, match.roleName, match.headline(level: current.level),
        match.setDescription,
      ]
      + match.reasons + match.conditions.map(\.explanation)).joined(separator: "\n")
  }
}

/// Headline assessment for the current artifact: grade or score, +20 outcomes, account odds.
struct AssessmentSummary: View {
  @ObservedObject var model: Model
  let artifact: Artifact

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if model.assessmentMode == .characters, let verdict = model.verdict {
        VerdictBanner(
          verdict: verdict, displayedCharacterID: model.selectedMatch?.characterID,
          displayedRoleID: model.selectedMatch?.roleID)
      }
      if model.assessmentMode == .characters {
        characterHero
      } else {
        profileHero
      }
      if let result = model.displayedPotential {
        forecast(result)
        Divider().overlay(Theme.hairline)
        AccountBlock(result: result, scope: model.displayedScope, finished: artifact.level == 20)
      } else {
        if let reason = unavailableReason {
          Label(reason, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        // A finished special-rule piece has a grade but no ordinary forecast.
        let grades = model.assessmentMode == .characters ? model.selectedMatch?.grades : nil
        if let line = rarityLine(grades, artifact: artifact) {
          Text(line).font(.caption).foregroundStyle(.secondary).help(rarityHelp(grades) ?? "")
        }
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var unavailableReason: String? {
    model.assessmentMode == .profile
      ? model.evaluationIssue : model.selectedMatch?.potentialUnavailableReason
  }

  private var characterHero: some View {
    let match = model.selectedMatch
    let headline = GradeHeadline(match: match, artifact: artifact)
    return HStack(alignment: .center, spacing: 14) {
      GradeBadge(tier: headline.tier, size: 64)
      VStack(alignment: .leading, spacing: 3) {
        Text(headline.caption).font(.caption.weight(.medium))
          .foregroundStyle(headline.kind == .needsReread ? Theme.attention : .secondary)
        Text(match?.characterName ?? "No character match").font(.title2.bold())
        if let match {
          HStack(spacing: 6) {
            Text(match.roleName).foregroundStyle(.secondary)
            Chip(
              text: match.setFit.shortLabel,
              tint: match.setFit == .offPiece ? .secondary : Theme.accent)
          }
          .font(.callout)
        } else {
          Text("Try a manual profile for other characters or stats.").foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private var profileHero: some View {
    HStack(spacing: 14) {
      Image(systemName: "slider.horizontal.3").font(.title).foregroundStyle(Theme.accent)
        .frame(width: 64, height: 64)
        .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: 15))
      VStack(alignment: .leading, spacing: 3) {
        Text("Manual profile · useful-roll points").font(.caption.weight(.medium))
          .foregroundStyle(.secondary)
        Text(model.profileName).font(.title2.bold())
        Text(model.profile.explanation).font(.callout).foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
    }
  }

  @ViewBuilder
  private func forecast(_ result: Potential) -> some View {
    let grades = model.assessmentMode == .characters ? model.selectedMatch?.grades : nil
    if artifact.level == 20 {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(score(result.currentScore, digits: 2))
          .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
        Text("final useful-roll points").foregroundStyle(.secondary)
      }
    } else {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("+20 OUTCOMES").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
          Spacer()
          Text(
            "Now \(score(result.currentScore, digits: 2)) · \(result.upgradesRemaining) random upgrades left"
          )
          .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        OutcomeLadder(result: result, grades: grades, digits: 2)
        HStack(spacing: 10) {
          Label(model.recommendation, systemImage: "arrow.up.forward.circle")
            .foregroundStyle(Theme.accent)
          if let chance = grades?.chanceOfAOrBetter {
            Spacer()
            Text("Reach A or S").foregroundStyle(.secondary)
            Text(percent(chance)).bold().monospacedDigit().foregroundStyle(Theme.tier(.a))
          }
        }
        .font(.callout)
        if model.assessmentMode == .characters, let match = model.selectedMatch {
          Text(UpgradeGuidance.helpfulRolls(artifact, usefulStats: match.usefulStats))
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    if let line = rarityLine(grades, artifact: artifact) {
      Text(line).font(.caption).foregroundStyle(.secondary).help(rarityHelp(grades) ?? "")
    }
  }
}

/// Selectable list of character roles plus the selected role's reasons and assumptions.
struct CharacterAssessmentView: View {
  @ObservedObject var model: Model
  let artifact: Artifact
  @State private var showingAllMatches = false

  var body: some View {
    let shortlist = model.characterShortlist
    let displayed = showingAllMatches ? shortlist.allMatches : shortlist.visibleMatches
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .firstTextBaseline) {
          Text("Potential users").font(.headline)
          Spacer()
          Text(RoleRowStatus.orderCaption).font(.caption).foregroundStyle(.secondary)
            .help(RoleRowStatus.orderHelp + CharacterAssessment.coverageDescription)
        }
        Text(
          "\(displayed.count) of \(shortlist.allMatches.count) eligible roles"
        )
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .help(CharacterAssessment.coverageDescription)
        if shortlist.allMatches.isEmpty {
          Text(CharacterRoles.noMatchDescription).font(.callout).foregroundStyle(.secondary)
        }
        ForEach(displayed) { match in
          row(
            match, label: shortlist.label(match),
            status: RoleRowStatus(match, standing: shortlist.standing(match), artifact: artifact))
        }
        if shortlist.allMatches.count > shortlist.visibleMatches.count {
          Button(
            showingAllMatches
              ? "Show shortlist" : "Show all \(shortlist.allMatches.count) eligible roles"
          ) {
            showingAllMatches.toggle()
          }
          .font(.caption)
        }
      }
      .frame(width: 280)
      if let match = model.selectedMatch {
        RoleDetail(match: match)
      }
    }
  }

  private func row(_ match: CharacterMatch, label: String, status: RoleRowStatus) -> some View {
    let selected = model.selectedMatch?.id == match.id
    let headline = GradeHeadline(match: match, artifact: artifact)
    return Button {
      model.selectedCharacterID = match.characterID
      model.selectedRoleID = match.roleID
    } label: {
      HStack(spacing: 10) {
        GradeBadge(tier: headline.tier, size: 28)
        VStack(alignment: .leading, spacing: 1) {
          Text(label).font(.callout.weight(.semibold))
          Text(headline.shortCaption).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer(minLength: 4)
        Chip(text: status.label)
      }
      .opacity(status.setAside && !selected ? 0.45 : 1)
      .padding(.horizontal, 8).padding(.vertical, 6)
      .contentShape(Rectangle())
      .background(
        selected ? Theme.accent.opacity(0.1) : Theme.surface,
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(selected ? Theme.accent.opacity(0.6) : .clear)
      }
    }
    .buttonStyle(.plain)
    .help(status.help ?? "")
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct RoleDetail: View {
  let match: CharacterMatch

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("\(match.characterName) · \(match.roleName)").font(.headline)
      FlowStats(title: "Scored core", stats: match.usefulStats, tint: Theme.accent)
      if !match.secondaryStats.isEmpty {
        FlowStats(title: "Utility, quarter weight", stats: match.secondaryStats, tint: .secondary)
      }
      VStack(alignment: .leading, spacing: 4) {
        ForEach(match.reasons, id: \.self) { reason in
          Label(reason, systemImage: "checkmark.circle").font(.caption)
            .labelStyle(BulletLabelStyle())
        }
      }
      DisclosureGroup("Build assumptions (\(match.conditions.count))") {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(Array(match.conditions.enumerated()), id: \.offset) { _, condition in
            Label(condition.explanation, systemImage: "questionmark.circle").font(.caption)
              .labelStyle(BulletLabelStyle())
          }
        }
        .padding(.top, 4)
      }
      .font(.caption)
      if let url = URL(string: match.role.source.url) {
        Link(
          "Source: \(match.role.source.section) (\(match.role.source.sourceVersion))",
          destination: url
        )
        .font(.caption)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

private struct FlowStats: View {
  let title: String
  let stats: [Stat]
  let tint: Color

  var body: some View {
    HStack(spacing: 5) {
      Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 110, alignment: .leading)
      ForEach(stats, id: \.self) { Chip(text: $0.label, tint: tint) }
    }
  }
}

struct BulletLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      configuration.icon.foregroundStyle(.secondary).imageScale(.small)
      configuration.title.fixedSize(horizontal: false, vertical: true)
    }
  }
}
