import LoupeCore
import SwiftUI

/// Runs of a top-level domain per upgrade, as "1 in N runs".
private func runs(_ drops: Double) -> String {
  "1 in \(roughCount(ResinCost.runs(forDrops: drops))) runs"
}

/// Every character with roles, by name, for pickers.
struct RosterEntry: Identifiable {
  let id: String
  let name: String
  let roles: [CharacterRole]

  static let all: [RosterEntry] = Set(CharacterRoles.all.map(\.characterID)).map { id in
    let roles = OwnedCharacter.roles(for: id)
    return RosterEntry(id: id, name: roles[0].characterName, roles: roles)
  }
  .sorted { $0.name < $1.name }
}

/// The dashboard's line about farming: the domain the account plan ranks first.
struct FarmingSummary: View {
  @ObservedObject var model: Model

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "leaf").foregroundStyle(Theme.accent)
      VStack(alignment: .leading, spacing: 1) {
        Text("What to farm").font(.callout.bold())
        Group {
          if let top = model.farmingPlan?.domains.first {
            Text(
              "\(top.domain.name) first"
                + (top.dropsPerUpgrade.map { " · ~\(runs($0)) per upgrade" } ?? "")
                + (model.ownedCharacters.isEmpty ? " · counting every character" : ""))
          } else if model.farmingPlan != nil {
            Text("No domain drops an upgrade often enough to count.")
          } else {
            Text("Working it out…")
          }
        }
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer()
      Button("Open Farming", systemImage: "arrow.up.forward.app") { model.showFarming?() }
        .controlSize(.small)
    }
    .padding(12)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .onAppear { model.requestFarmingPlan() }
  }
}

/// The Farming window: what to farm for one character, and for the whole account.
struct FarmingWindow: View {
  @ObservedObject var model: Model
  @State private var tab = Tab.character
  @State private var editor = false

  enum Tab: Hashable { case character, account }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Picker("View", selection: $tab) {
          Text("By character").tag(Tab.character)
          Text("Account").tag(Tab.account)
        }
        .pickerStyle(.segmented).labelsHidden().frame(width: 240)
        Spacer()
        if model.farmingRefreshing {
          ProgressView().controlSize(.small).help("Updating for your characters and inventory")
        }
        Button("My characters…", systemImage: "person.2") { editor = true }
        Text(
          model.ownedCharacters.isEmpty
            ? "None entered" : "\(model.ownedCharacters.count) owned"
        )
        .font(.caption).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16).padding(.vertical, 10)
      Divider()
      switch tab {
      case .character: CharacterFarmingTab(model: model)
      case .account: AccountFarmingTab(model: model, editor: $editor)
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .preferredColorScheme(.dark)
    .tint(Theme.accent)
    .frame(minWidth: 820, minHeight: 560)
    .sheet(isPresented: $editor) { OwnedCharactersEditor(model: model) }
    .onAppear { model.requestFarmingPlan() }
  }
}

// MARK: By character

private struct CharacterFarmingTab: View {
  @ObservedObject var model: Model
  @State private var selection: String?
  @State private var search = ""

  var body: some View {
    let owned = Set(model.ownedCharacters.map(\.characterID))
    let matching = RosterEntry.all.filter {
      search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
    }
    HStack(spacing: 0) {
      VStack(spacing: 8) {
        TextField("Search characters", text: $search).textFieldStyle(.roundedBorder)
          .padding([.horizontal, .top], 10)
        List(selection: $selection) {
          if !owned.isEmpty {
            Section("Owned") {
              ForEach(matching.filter { owned.contains($0.id) }) { row($0) }
            }
          }
          Section(owned.isEmpty ? "Characters" : "Others") {
            ForEach(matching.filter { !owned.contains($0.id) }) { row($0) }
          }
        }
        .listStyle(.sidebar)
      }
      .frame(width: 230)
      Divider()
      if let selection, let entry = RosterEntry.all.first(where: { $0.id == selection }) {
        CharacterFarmingDetail(model: model, entry: entry).id(entry.id)
      } else {
        ContentUnavailableView(
          "Choose a character", systemImage: "person.crop.square",
          description: Text("See what each slot wears and what its set's domain can still improve.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .onAppear {
      if selection == nil { selection = model.ownedCharacters.first?.characterID }
    }
  }

  private func row(_ entry: RosterEntry) -> some View {
    let building = model.ownedCharacters.first { $0.characterID == entry.id }?.building ?? false
    return HStack {
      Text(entry.name)
      Spacer()
      if building {
        Image(systemName: "star.fill").imageScale(.small).foregroundStyle(Theme.attention)
          .help("Building now")
      }
    }
    .tag(entry.id)
  }
}

private struct CharacterFarmingDetail: View {
  @ObservedObject var model: Model
  let entry: RosterEntry
  /// The role shown for a character the player doesn't own; an owned one shows its saved role.
  @State private var viewedRoleID: String?
  @State private var build: CharacterFarming?

  private var owned: OwnedCharacter? {
    model.ownedCharacters.first { $0.characterID == entry.id }
  }
  private var role: CharacterRole {
    let id = owned?.roleID ?? viewedRoleID
    return entry.roles.first { $0.roleID == id } ?? entry.roles[0]
  }
  private var roleBinding: Binding<String> {
    Binding(
      get: { role.roleID },
      set: { id in
        if let index = model.ownedCharacters.firstIndex(where: { $0.characterID == entry.id }) {
          model.ownedCharacters[index].roleID = id
        } else {
          viewedRoleID = id
        }
      })
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        header
        if let build, build.role.roleID == role.roleID {
          content(build)
        } else {
          ProgressView().controlSize(.small)
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task(id: TaskKey(roleID: role.roleID, finished: finished)) {
      let role = role
      let artifacts = finished
      let worker = Task.detached(priority: .userInitiated) {
        FarmingPlan.character(role, inventory: artifacts)
      }
      let result = await withTaskCancellationHandler {
        await worker.value
      } onCancel: {
        worker.cancel()
      }
      // A newer role or inventory has replaced this calculation.
      guard !Task.isCancelled else { return }
      build = result
    }
  }

  /// Only finished five-star pieces count, so collecting new drops doesn't redo the build.
  private var finished: [Artifact] {
    model.inventory.artifacts.filter { $0.level == 20 && $0.rarity == 5 }
  }

  private struct TaskKey: Equatable {
    let roleID: String
    let finished: [Artifact]
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(entry.name).font(.title2.bold())
      if entry.roles.count > 1 {
        Picker("Role", selection: roleBinding) {
          ForEach(entry.roles) { Text($0.roleName).tag($0.roleID) }
        }
        .labelsHidden().fixedSize()
      } else {
        Text(role.roleName).foregroundStyle(.secondary)
      }
      Spacer()
      if let owned {
        Toggle(isOn: building(owned)) { Label("Building now", systemImage: "star") }
          .toggleStyle(.button).controlSize(.small)
          .help("Counts double in the account plan")
      } else {
        Button("I own this character", systemImage: "plus") {
          model.ownedCharacters.append(
            OwnedCharacter(characterID: entry.id, roleID: role.roleID))
        }
        .controlSize(.small)
      }
    }
  }

  private func building(_ owned: OwnedCharacter) -> Binding<Bool> {
    Binding(
      get: { owned.building },
      set: { on in
        guard let index = model.ownedCharacters.firstIndex(where: { $0.id == owned.id })
        else { return }
        model.ownedCharacters[index].building = on
      })
  }

  @ViewBuilder private func content(_ build: CharacterFarming) -> some View {
    if let set = build.set {
      VStack(alignment: .leading, spacing: 4) {
        Text(
          build.domain.map { "Farm \(set) at \($0.name)" }
            ?? "\(set) drops only from bosses and the Artifact Strongbox"
        )
        .font(.headline)
        if !build.hasDomain {
          Text("No domain drops it, so there's no run estimate.")
            .font(.callout).foregroundStyle(.secondary)
        } else if let drops = build.dropsPerUpgrade {
          Text(
            "About \(runs(drops)) drops an upgrade for this build, "
              + ResinCost.duration(forDrops: drops) + " of resin."
          )
          .font(.callout).foregroundStyle(.secondary)
          .help(ResinCost.breakdown(forDrops: drops))
        } else {
          Text("Every slot is filled; no drop of the set can beat what it wears.")
            .font(.callout).foregroundStyle(.secondary)
        }
        let others = role.sets.map(\.name).filter { $0 != set }
        if !others.isEmpty {
          Text("Also listed: " + others.joined(separator: ", ")).font(.caption)
            .foregroundStyle(.secondary)
        }
      }
      SlotTable(build: build)
      Text(
        "Wearing is the best saved +20 piece of the set for each slot, except one off-set slot when another set's piece is rarer there. An upgrade is a drop of the set that finishes A or better and beats what's worn. Unscanned pieces make slots look emptier than they are."
      )
      .font(.caption).foregroundStyle(.secondary)
    } else {
      Text("This role lists no five-star set to farm.").foregroundStyle(.secondary)
    }
  }
}

private struct SlotTable: View {
  let build: CharacterFarming

  var body: some View {
    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
      GridRow {
        Text("SLOT")
        Text("WEARING")
        Text("GRADE")
        Text("WANT")
        Text("UPGRADE").gridColumnAlignment(.trailing)
      }
      .font(.caption2.bold()).foregroundStyle(.secondary)
      Divider()
      ForEach(build.slots) { need in
        GridRow {
          Text(need.slot.label).font(.callout.bold())
          worn(need)
          grade(need)
          Text(need.mains.map(\.label).joined(separator: " or ")).font(.caption)
            .foregroundStyle(.secondary).lineLimit(2)
          Group {
            if need.isFilled {
              Text("Done").foregroundStyle(Theme.accent)
            } else if let drops = need.dropsPerUpgrade, build.hasDomain {
              Text(runs(drops)).help(ResinCost.breakdown(forDrops: drops))
            } else {
              Text("—").foregroundStyle(.secondary)
            }
          }
          .font(.caption.monospacedDigit())
        }
      }
    }
    .padding(14)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  @ViewBuilder private func worn(_ need: FarmingNeed) -> some View {
    if let best = need.best {
      VStack(alignment: .leading, spacing: 1) {
        Text(need.offSet ? "\(best.setName) (off-set)" : best.setName).font(.caption)
          .lineLimit(1)
        Text(best.main.label).font(.caption2).foregroundStyle(.secondary)
      }
    } else {
      Text("None saved").font(.caption).foregroundStyle(Theme.attention)
    }
  }

  @ViewBuilder private func grade(_ need: FarmingNeed) -> some View {
    if let grade = need.bestGrade {
      Text(grade.rawValue).font(.callout.bold()).foregroundStyle(Theme.tier(grade))
    } else {
      Text(need.best == nil ? "—" : "Main").font(.caption).foregroundStyle(.secondary)
        .help(need.best == nil ? "" : "Valued for its main stat alone")
    }
  }
}

// MARK: Account

private struct AccountFarmingTab: View {
  @ObservedObject var model: Model
  @Binding var editor: Bool
  @State private var allDomains = false
  private static let shown = 5

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        scope
        if let plan = model.farmingPlan {
          domains(plan)
          sets(plan)
          notes(plan)
        } else {
          ProgressView().controlSize(.small)
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var scope: some View {
    let building = model.ownedCharacters.filter(\.building).count
    return HStack(spacing: 8) {
      Image(systemName: model.ownedCharacters.isEmpty ? "person.3" : "person.2.fill")
        .foregroundStyle(Theme.accent)
      if model.ownedCharacters.isEmpty {
        Text(
          "Counting every character, since you haven't said who you own. Enter your characters for advice about your account."
        )
        Button("Enter characters…") { editor = true }.buttonStyle(.link)
      } else {
        Text(
          "Counting your \(model.ownedCharacters.count) characters"
            + (building > 0 ? ", the \(building) you're building now counted double." : ".")
        )
      }
    }
    .font(.callout)
  }

  @ViewBuilder private func domains(_ plan: FarmingPlan.Result) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Domains").font(.headline)
      if plan.domains.isEmpty {
        Text("No domain drops an upgrade often enough to count.").font(.callout)
          .foregroundStyle(.secondary)
      }
      let shown = allDomains ? plan.domains : Array(plan.domains.prefix(Self.shown))
      ForEach(Array(shown.enumerated()), id: \.element.id) { index, suggestion in
        DomainRow(rank: index + 1, suggestion: suggestion)
      }
      if plan.domains.count > Self.shown {
        Button(allDomains ? "Show fewer" : "Show all \(plan.domains.count) domains") {
          allDomains.toggle()
        }
        .buttonStyle(.link).font(.caption)
      }
    }
  }

  @ViewBuilder private func sets(_ plan: FarmingPlan.Result) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        Text("Sets").font(.headline)
        Text("Weakest first. Ready slots wear an A or better, or a piece valued for its main.")
          .font(.caption).foregroundStyle(.secondary)
      }
      Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
        GridRow {
          Text("SET")
          Text("")
          Text("READY")
          Text("USED BY")
          Text("UPGRADE").gridColumnAlignment(.trailing)
        }
        .font(.caption2.bold()).foregroundStyle(.secondary)
        Divider()
        ForEach(plan.sets) { strength in
          GridRow {
            VStack(alignment: .leading, spacing: 1) {
              Text(strength.set).font(.callout).lineLimit(1)
              Text(strength.domain?.name ?? "Bosses and strongboxes").font(.caption2)
                .foregroundStyle(.secondary).lineLimit(1)
            }
            Text(strength.level.rawValue).font(.caption.bold())
              .foregroundStyle(color(strength.level))
            Text("\(strength.readySlots) of \(strength.totalSlots)")
              .font(.caption.monospacedDigit())
            Text(strength.builds.map(\.role.characterName).joined(separator: ", "))
              .font(.caption).foregroundStyle(.secondary).lineLimit(2)
              .frame(maxWidth: 280, alignment: .leading)
            Group {
              if !strength.hasDomain {
                Text("—").foregroundStyle(.secondary).help("No domain drops this set")
              } else if strength.upgradesPerDrop > 0 {
                Text(runs(1 / strength.upgradesPerDrop))
              } else {
                Text("Done").foregroundStyle(Theme.accent)
              }
            }
            .font(.caption.monospacedDigit())
          }
        }
      }
      .padding(14)
      .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
  }

  private func color(_ level: SetStrength.Level) -> Color {
    switch level {
    case .strong: Theme.accent
    case .fair: .secondary
    case .weak: Theme.attention
    }
  }

  @ViewBuilder private func notes(_ plan: FarmingPlan.Result) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if !plan.unfarmable.isEmpty {
        Text(
          "No five-star set to farm for "
            + plan.unfarmable.map(\.characterName).joined(separator: ", ") + "."
        )
      }
      Text(
        "An upgrade is a drop of a character's four-piece set that finishes A or better and beats what it wears. Rates add up over characters, so a piece two of them could use counts twice. Off-set drops come from every domain alike, so they don't change the order. Unscanned pieces make sets look weaker than they are."
      )
    }
    .font(.caption).foregroundStyle(.secondary)
  }
}

private struct DomainRow: View {
  let rank: Int
  let suggestion: DomainSuggestion
  private static let needsShown = 4

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text("\(rank)").font(.callout.monospacedDigit().bold()).foregroundStyle(Theme.accent)
          .frame(width: 18, alignment: .leading)
        VStack(alignment: .leading, spacing: 1) {
          Text(suggestion.domain.name).font(.callout.bold())
          Text(suggestion.domain.sets.joined(separator: " · ")).font(.caption)
            .foregroundStyle(.secondary)
        }
        Spacer()
        if let drops = suggestion.dropsPerUpgrade {
          VStack(alignment: .trailing, spacing: 1) {
            Text("~1 upgrade per \(roughCount(ResinCost.runs(forDrops: drops))) runs")
              .font(.caption.bold()).monospacedDigit()
            Text(ResinCost.duration(forDrops: drops) + " of resin").font(.caption2)
              .foregroundStyle(.secondary)
          }
          .help(
            "Expected upgrades summed over your characters' slots. "
              + ResinCost.breakdown(forDrops: drops))
        }
      }
      VStack(alignment: .leading, spacing: 3) {
        ForEach(suggestion.needs.prefix(Self.needsShown)) { need in
          HStack(spacing: 6) {
            if need.weight > 1 {
              Image(systemName: "star.fill").imageScale(.small).foregroundStyle(Theme.attention)
            }
            Text("\(need.role.characterName) · \(need.set) \(need.slot.label.lowercased())")
              .lineLimit(1)
            Spacer(minLength: 4)
            Text(Self.standing(need)).foregroundStyle(.secondary)
            if let drops = need.dropsPerUpgrade {
              Text(runs(drops)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 96, alignment: .trailing)
            }
          }
          .font(.caption)
          .help(need.role.roleName)
        }
        if suggestion.needs.count > Self.needsShown {
          Text("and \(suggestion.needs.count - Self.needsShown) more slots").font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.leading, 28)
    }
    .padding(10)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }

  static func standing(_ need: FarmingNeed) -> String {
    guard need.best != nil else { return "none saved" }
    let grade = need.bestGrade.map { "wearing \($0.rawValue)" } ?? "wearing"
    return need.offSet ? grade + " off-set" : grade
  }
}

// MARK: Owned characters

/// The characters the player owns, the role each is built for, and which are being built now.
struct OwnedCharactersEditor: View {
  @ObservedObject var model: Model
  @Environment(\.dismiss) private var dismiss
  @State private var search = ""
  @State private var ownedOnly = false

  var body: some View {
    let owned = Set(model.ownedCharacters.map(\.characterID))
    let rows = RosterEntry.all.filter {
      (!ownedOnly || owned.contains($0.id))
        && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search))
    }
    VStack(alignment: .leading, spacing: 12) {
      Text("My characters").font(.title2.bold())
      Text(
        "Optional. Tick the characters you own so the account plan counts only them. Star the ones you're building now to count them double. Loupe can't see your account; this stays on this Mac."
      )
      .font(.callout).foregroundStyle(.secondary)
      HStack {
        TextField("Search characters", text: $search).textFieldStyle(.roundedBorder)
        Toggle("Owned only", isOn: $ownedOnly).toggleStyle(.checkbox)
      }
      List(rows) { entry in
        OwnedRow(model: model, entry: entry)
      }
      .frame(minHeight: 360)
      HStack {
        Text("\(model.ownedCharacters.count) owned").font(.caption).foregroundStyle(.secondary)
        Button("Clear all", role: .destructive) { model.ownedCharacters = [] }
          .disabled(model.ownedCharacters.isEmpty)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 600, height: 640)
  }
}

private struct OwnedRow: View {
  @ObservedObject var model: Model
  let entry: RosterEntry

  private var index: Int? { model.ownedCharacters.firstIndex { $0.characterID == entry.id } }

  var body: some View {
    HStack(spacing: 10) {
      Toggle(
        entry.name,
        isOn: Binding(
          get: { index != nil },
          set: { on in
            if on {
              if index == nil {
                model.ownedCharacters.append(OwnedCharacter(characterID: entry.id))
              }
            } else {
              model.ownedCharacters.removeAll { $0.characterID == entry.id }
            }
          })
      )
      .toggleStyle(.checkbox)
      Spacer()
      if let owned = index.map({ model.ownedCharacters[$0] }) {
        if entry.roles.count > 1 {
          Picker("Role", selection: update(\.roleID, of: owned)) {
            ForEach(entry.roles) { Text($0.roleName).tag($0.roleID) }
          }
          .labelsHidden().fixedSize().controlSize(.small)
        }
        Toggle(isOn: update(\.building, of: owned)) {
          Image(systemName: owned.building ? "star.fill" : "star")
            .foregroundStyle(owned.building ? Theme.attention : .secondary)
        }
        .toggleStyle(.button).buttonStyle(.borderless)
        .help("Building now: counts double in the account plan")
      }
    }
  }

  /// Edits one field of an owned entry, found again by character so a list change between
  /// renders can't write to another entry.
  private func update<Value>(
    _ field: WritableKeyPath<OwnedCharacter, Value>, of owned: OwnedCharacter
  ) -> Binding<Value> {
    Binding(
      get: { owned[keyPath: field] },
      set: { value in
        guard let index = model.ownedCharacters.firstIndex(where: { $0.id == owned.id })
        else { return }
        model.ownedCharacters[index][keyPath: field] = value
      })
  }
}
