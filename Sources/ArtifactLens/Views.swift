import ArtifactCore
import SwiftUI

func percent(_ value: Double) -> String {
  if value > 0 && value < 0.001 { return "<0.1%" }
  if value < 1 && value > 0.999 { return ">99.9%" }
  return (value * 100).formatted(.number.precision(.fractionLength(1))) + "%"
}

struct Dashboard: View {
  @ObservedObject var model: Model
  @State private var textEditor = false
  @State private var guide = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      HStack(spacing: 0) {
        ScrollView { Sidebar(model: model, textEditor: $textEditor).padding(14) }
          .frame(width: 290)
          .background(Color.black.opacity(0.12))
        Divider()
        ScrollView {
          VStack(alignment: .leading, spacing: 18) {
            if let artifact = model.current {
              HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                  ArtifactCard(artifact: artifact, verified: model.stability.isVerified)
                  saveButtons
                }
                .frame(width: 250)
                AssessmentSummary(model: model, artifact: artifact)
              }
              if model.assessmentMode == .characters {
                CharacterAssessmentView(model: model, artifact: artifact)
              } else if let potential = model.potential {
                PotentialView(model: model, potential: potential)
              }
            } else {
              ContentUnavailableView {
                Label("Waiting for a clear artifact", systemImage: "viewfinder")
              } description: {
                Text(
                  "Choose the game window, open Inventory, and select a five-star piece. Screens stay on this Mac."
                )
              } actions: {
                Button("Scan guide") { guide = true }
              }
              .frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            InventoryView(model: model)
          }
          .padding(20)
        }
      }
      Divider()
      HStack(spacing: 8) {
        StatusDot(verified: model.stability.isVerified, active: model.enabled)
        Text(model.status).font(.caption).lineLimit(2)
        Spacer()
      }
      .padding(.horizontal, 14).padding(.vertical, 9)
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .preferredColorScheme(.dark)
    .tint(Theme.accent)
    .frame(minWidth: 1010, minHeight: 740)
    .sheet(isPresented: $textEditor) { CardTextEditor(model: model) }
    .sheet(isPresented: $guide) { ScanGuide() }
    .background(DiagnosticPresentation(flow: model.diagnostics))
    .alert(
      "Check this before continuing",
      isPresented: Binding(get: { model.issue != nil }, set: { if !$0 { model.issue = nil } })
    ) {
      Button("OK") { model.issue = nil }
    } message: {
      Text(model.issue ?? "")
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image(systemName: "viewfinder").font(.title2.weight(.semibold)).foregroundStyle(Theme.accent)
        .frame(width: 38, height: 38)
        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
      VStack(alignment: .leading, spacing: 1) {
        Text("Artifact Lens").font(.title3.bold())
        Text("What each piece could become, and who can use it").font(.caption)
          .foregroundStyle(.secondary)
      }
      readerPill
      Spacer()
      Button("Choose game window", systemImage: "macwindow") { model.chooseWindow() }
        .buttonStyle(.borderedProminent).disabled(!model.enabled)
      Button(model.enabled ? "Disable" : "Enable", systemImage: "power") {
        model.setEnabled(!model.enabled)
      }
      .help(
        model.enabled
          ? "Stop capture and OCR and clear live results. Saved inventory stays."
          : "Resume reading the selected window.")
      Button("Report issue", systemImage: "exclamationmark.bubble") { model.reportIssue() }
        .disabled(!model.diagnostics.canRequest)
      Button("Guide", systemImage: "questionmark.circle") { guide = true }
    }
    .padding(.horizontal, 18).padding(.vertical, 12)
  }

  private var readerPill: some View {
    let (text, color): (String, Color) =
      !model.enabled
      ? ("Disabled", .secondary)
      : model.current == nil
        ? ("Waiting", .secondary)
        : model.stability.isVerified ? ("Verified", Theme.accent) : ("Rechecking", Theme.attention)
    return HStack(spacing: 5) {
      StatusDot(verified: model.stability.isVerified, active: model.enabled && model.current != nil)
      Text(text).font(.caption.weight(.semibold)).foregroundStyle(color)
    }
    .padding(.horizontal, 8).padding(.vertical, 3)
    .background(Theme.surfaceStrong, in: Capsule())
  }

  private var saveButtons: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Button(model.linkedID == nil ? "Save artifact" : "Update linked") { model.saveCurrent() }
          .buttonStyle(.borderedProminent)
        Button("Save copy") { model.saveCurrent(copy: true) }
          .help("Save an additional identical physical copy.")
        if model.linkedID != nil {
          Button("Unlink") {
            model.linkedID = nil
            model.evaluate()
          }
        }
      }
      .disabled(!model.canSaveCurrent)
      .controlSize(.small)
      if model.linkedID != nil {
        Label("Linked upgrade", systemImage: "link").font(.caption).foregroundStyle(Theme.accent)
      }
    }
  }
}

private struct Sidebar: View {
  @ObservedObject var model: Model
  @Binding var textEditor: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Panel(title: "Evaluate", systemImage: "scope") {
        Picker("Evaluate", selection: $model.assessmentMode) {
          ForEach(AssessmentMode.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented).labelsHidden()
        LabeledContent("Compare with") {
          Picker("Compare with", selection: $model.scope) {
            Text("All sets").tag(ComparisonScope.offPiece)
            Text("Same set").tag(ComparisonScope.sameSet)
          }
          .pickerStyle(.segmented).labelsHidden().frame(width: 150)
        }
        .font(.callout)
        Text("Saved +20 pieces with the same slot and main stat.")
          .font(.caption).foregroundStyle(.secondary)
        if model.assessmentMode == .profile { profileControls }
        DisclosureGroup("How scores work") {
          Text(
            "One maximum-sized useful roll = 1 point. Equal CRIT Rate and CRIT DMG roll weights already account for their 1:2 stat amounts. Scores are a screen, not damage. Median and P90 are the scores reached by 50% and 90% of ordinary upgrade outcomes; best possible is a ceiling. None of these are player percentiles."
          )
          .font(.caption).foregroundStyle(.secondary).padding(.top, 4)
          .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
      }
      Panel(title: "Reading", systemImage: "text.viewfinder") {
        Toggle("Collect cards as I browse", isOn: $model.scanMode).disabled(!model.enabled)
        Toggle("Crafted / guaranteed rolls", isOn: $model.special)
          .help("Mark crafted pieces before reading. Reshaping odds are not modeled.")
        Text("Ordinary five-star drops only.").font(.caption).foregroundStyle(.secondary)
        Button("Paste / correct card text", systemImage: "square.and.pencil") {
          textEditor = true
        }
        .disabled(!model.enabled)
      }
      .toggleStyle(.switch).controlSize(.small)
      Panel(title: "Overlay", systemImage: "rectangle.inset.topright.filled") {
        Toggle("Expanded", isOn: $model.overlayExpanded).toggleStyle(.switch).controlSize(.small)
        Button("Reset placement", systemImage: "arrow.uturn.backward") {
          model.resetOverlayPlacement?()
        }
        Text(model.placementStatus).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
          GridRow {
            Text("Expand").font(.caption)
            TextField("Expand shortcut", text: $model.expandShortcut)
          }
          GridRow {
            Text("Reader").font(.caption)
            TextField("Enable shortcut", text: $model.enableShortcut)
          }
        }
        .textFieldStyle(.roundedBorder)
        .help(
          "Use option, shift, control, or command + a letter, digit, or backtick. Expanding never enables capture."
        )
        HStack {
          Button("Apply shortcuts") { model.applyShortcuts?() }
          Spacer()
        }
        if !model.shortcutStatus.isEmpty {
          Text(model.shortcutStatus).font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Panel(title: "Diagnostics", systemImage: "stethoscope") {
        DiagnosticControls(flow: model.diagnostics, report: model.reportIssue)
        Divider()
        Button("Record 40 test frames", systemImage: "record.circle") {
          model.capture.recordSequence()
        }
        .disabled(!model.enabled || model.isRecording)
        Text(model.recordingStatus).font(.caption2).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

  @ViewBuilder
  private var profileControls: some View {
    Picker("Profile", selection: $model.profileName) {
      ForEach(Profile.presets) { Text($0.id).tag($0.id) }
      Text("Custom").tag("Custom")
    }
    if model.profileName == "Custom" {
      Text("Roll weights (0–100)").font(.caption.bold())
      Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
        ForEach(Array(stride(from: 0, to: Stat.substats.count, by: 2)), id: \.self) { index in
          GridRow {
            ForEach(Stat.substats[index..<min(index + 2, Stat.substats.count)]) { stat in
              weightField(stat)
            }
          }
        }
      }
    } else {
      Text(model.profile.explanation).font(.caption).foregroundStyle(.secondary)
    }
  }

  private func weightField(_ stat: Stat) -> some View {
    HStack(spacing: 4) {
      Text(stat.label).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
      Spacer(minLength: 2)
      TextField(
        "Roll weight",
        value: Binding(
          get: { model.customWeights[stat, default: 0] },
          set: { model.customWeights[stat] = min(100, max(0, $0)) }), format: .number
      )
      .labelsHidden().frame(width: 38).textFieldStyle(.roundedBorder).font(.caption)
    }
  }
}

struct ArtifactCard: View {
  let artifact: Artifact
  var verified = true

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 3) {
          Text(artifact.setName).font(.headline).lineLimit(2)
          Text("\(artifact.slot.label) · \(artifact.main.label)").font(.callout)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Text("+\(artifact.level)")
          .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
          .foregroundStyle(Theme.accent)
      }
      Divider().overlay(Theme.hairline)
      ForEach(artifact.substats, id: \.key) { stat in
        HStack {
          Text(stat.key.label).foregroundStyle(.secondary)
          Spacer()
          Text(stat.key.display(stat.value)).monospacedDigit()
        }
        .font(.callout)
      }
      if let stat = artifact.unactivated {
        HStack {
          Text("\(stat.key.label) at +4")
          Spacer()
          Text(stat.key.display(stat.value)).monospacedDigit()
        }
        .font(.callout).foregroundStyle(.tertiary)
      }
      if !verified {
        Label("Rechecking. Saving is paused.", systemImage: "arrow.triangle.2.circlepath")
          .font(.caption).foregroundStyle(Theme.attention)
      }
      if artifact.rule != .ordinary {
        Label("Special rolls: ordinary odds disabled", systemImage: "wand.and.stars")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .padding(14)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

/// Manual-profile detail: saved-rank odds, current leaders, and other preset profiles.
struct PotentialView: View {
  @ObservedObject var model: Model
  let potential: Potential

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      VStack(alignment: .leading, spacing: 10) {
        Text("Saved ranking").font(.headline)
        if potential.bestRank != nil {
          ForEach(potential.rankChances.filter { $0.rank <= 3 }) { chance in
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text("Top \(chance.rank) or tied").font(.callout)
                Spacer()
                Text(percent(chance.probability)).monospacedDigit().bold()
              }
              ProgressView(value: chance.probability)
            }
          }
          if !potential.leaders.isEmpty {
            Text("Current leaders").font(.caption.bold()).foregroundStyle(.secondary)
              .padding(.top, 4)
            ForEach(Array(potential.leaders.enumerated()), id: \.element.id) { index, artifact in
              HStack {
                Text("#\(index + 1)").foregroundStyle(Theme.accent).monospacedDigit()
                Text(artifact.setName).lineLimit(1)
                Spacer()
                Text(score(Double(model.profile.score(artifact.substats)) / 1000, digits: 2))
                  .monospacedDigit()
              }
              .font(.caption)
            }
          }
        } else {
          Text("Save comparable +20 pieces to see ranks.").font(.callout)
            .foregroundStyle(.secondary)
        }
        Text("Not a discard verdict. Check other profiles and set value.").font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(12)
      .frame(width: 280, alignment: .leading)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
      ProfileOverview(model: model)
    }
  }
}

struct ProfileOverview: View {
  @ObservedObject var model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Other profiles").font(.headline)
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
        GridRow {
          Text("PROFILE")
          Text("BEST RANK")
          Text("TOP 1 / TIED")
          Text("BEST")
        }
        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
        ForEach(model.allProfiles, id: \.name) { item in
          GridRow {
            Button(item.name) { model.profileName = item.name }.buttonStyle(.plain)
              .foregroundStyle(item.name == model.profileName ? Theme.accent : .primary)
            Text(item.result.bestRank.map { "#\($0)" } ?? "No baseline")
              .foregroundStyle(item.result.bestRank == nil ? .secondary : .primary)
            Text(item.result.rankChances.first.map { percent($0.probability) } ?? "–")
            Text(score(item.result.maximumScore, digits: 2))
          }
          .font(.caption).monospacedDigit()
        }
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }
}

struct InventoryView: View {
  @ObservedObject var model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Text("Saved inventory").font(.headline)
        Chip(text: "\(model.inventory.artifacts.count) saved")
        Chip(text: "\(model.upgradedCount) at +20")
        Chip(text: "Partial", systemImage: "circle.dashed")
          .help("Unscanned pieces can change every rank.")
        Spacer()
        Button("Import", systemImage: "square.and.arrow.down") { model.importInventory() }
          .help("Import GOOD JSON or an Artifact Lens backup. Merges without deleting.")
        Button("Export", systemImage: "square.and.arrow.up") { model.exportInventory() }
        Button("Undo", systemImage: "arrow.uturn.backward") { model.undo() }
          .help("Undo the last inventory edit this session.")
      }
      .controlSize(.small)
      InventoryCoverageView(artifacts: model.inventory.artifacts, current: model.current)
      TextField("Filter set, slot, main stat, or +20", text: $model.search)
        .textFieldStyle(.roundedBorder)
      Text(
        "To track an upgrade, link its record, then save after each checkpoint. Identical cards are deduplicated; use Save copy for real duplicates."
      )
      .font(.caption).foregroundStyle(.secondary)
      LazyVStack(alignment: .leading, spacing: 6) {
        ForEach(model.visibleInventory) { artifact in
          let linked = model.linkedID == artifact.id
          HStack(spacing: 12) {
            Text("+\(artifact.level)").font(.callout.monospacedDigit().bold())
              .foregroundStyle(artifact.level == 20 ? Theme.accent : .secondary)
              .frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: 6) {
                Text(artifact.setName).font(.callout).lineLimit(1)
                Text("\(artifact.slot.label) · \(artifact.main.label)").font(.caption)
                  .foregroundStyle(.secondary)
              }
              Text(
                artifact.substats.map { "\($0.key.label) \($0.key.display($0.value))" }
                  .joined(separator: "  ·  ")
              )
              .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button(linked ? "Linked" : "Link upgrade", systemImage: "link") { model.link(artifact) }
              .tint(linked ? Theme.accent : nil)
            Button("Remove", systemImage: "trash", role: .destructive) { model.remove(artifact) }
              .labelStyle(.iconOnly).help("Remove from saved inventory")
          }
          .controlSize(.small)
          .padding(.horizontal, 10).padding(.vertical, 7)
          .background(
            linked ? Theme.accent.opacity(0.08) : Theme.surface,
            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
      }
    }
  }
}

struct CardTextEditor: View {
  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss
  @State private var text = ""
  @State private var confirmed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Correct a card reading").font(.title2.bold())
      Text(
        "Include slot, main stat and value, +level, each substat, and the set name ending with a colon. Applying text stops live capture."
      )
      .foregroundStyle(.secondary)
      TextEditor(text: $text).font(.body.monospaced()).frame(minHeight: 300)
        .scrollContentBackground(.hidden).padding(6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
      Toggle("I verified this is a five-star artifact", isOn: $confirmed)
      HStack {
        Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
        Spacer()
        Button("Use this card") {
          model.useText(text, confirmed: confirmed)
          dismiss()
        }
        .buttonStyle(.borderedProminent).disabled(!confirmed)
      }
    }
    .padding(24).frame(width: 580).onAppear { text = model.rawText }
  }
}

struct ScanGuide: View {
  @Environment(\.dismiss) private var dismiss
  private let steps: [(String, String)] = [
    ("line.3.horizontal.decrease.circle", "In Genshin Inventory, filter to five-star artifacts."),
    ("arrow.up.arrow.down", "Sort by level. Start with +20 pieces, including equipped ones."),
    ("macwindow", "Choose the game window in the macOS sharing picker."),
    (
      "tray.and.arrow.down",
      "Turn on Collect cards as I browse. Select each piece and wait for Verified."
    ),
    (
      "checkmark.circle",
      "Check the saved count and stats. Fix misses with Paste / correct card text."
    ),
    ("pause.circle", "Turn collection off. Browse +0 pieces to see their potential."),
    ("link", "Save and link a candidate before upgrading. Update it after each checkpoint."),
  ]

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("Build your comparison baseline").font(.title2.bold())
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
          HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(index + 1)").font(.caption.bold()).monospacedDigit()
              .frame(width: 20, height: 20)
              .background(Theme.accent.opacity(0.15), in: Circle())
              .foregroundStyle(Theme.accent)
            Image(systemName: step.0).foregroundStyle(.secondary).frame(width: 18)
            Text(step.1).fixedSize(horizontal: false, vertical: true)
          }
        }
      }
      Label {
        Text(
          "No automated clicks, upgrades, or salvage. Only the selected window is read, on this Mac. Opt-in diagnostics keep crops in memory until you save a report; test recording saves full-window frames. Both may include UID or chat. Nothing is uploaded."
        )
      } icon: {
        Image(systemName: "lock.shield")
      }
      .font(.callout).foregroundStyle(.secondary)
      .padding(10).background(Theme.surface, in: RoundedRectangle(cornerRadius: 8))
      Text(
        "The baseline stays labeled partial. Unscanned pieces, duplicates, discarded pieces, and set bonuses can change the practical result."
      )
      .font(.callout).foregroundStyle(.secondary)
      HStack {
        Spacer()
        Button("Got it") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(28).frame(width: 600)
  }
}
