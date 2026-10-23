import LoupeCore
import SwiftUI

struct InventoryCategory: Identifiable, Equatable {
  let slot: Slot
  let main: Stat
  let count: Int
  var id: String { "\(slot.rawValue)/\(main.rawValue)" }

  static func summarize(_ artifacts: [Artifact]) -> [Self] {
    Slot.allCases.flatMap { slot in
      slot.mainStats.map { main in
        Self(
          slot: slot, main: main,
          count: artifacts.filter { $0.level == 20 && $0.slot == slot && $0.main == main }.count)
      }
    }
  }
}

struct InventoryCoverageView: View {
  let artifacts: [Artifact]
  let current: Artifact?

  var body: some View {
    let categories = InventoryCategory.summarize(artifacts)
    let sparse = categories.filter { $0.count < 3 }.count
    DisclosureGroup {
      VStack(alignment: .leading, spacing: 10) {
        Text(
          "Counts include all sets. Groups under three pieces cannot support a saved top-three comparison. Counts do not show that the scan is complete."
        )
        .font(.caption).foregroundStyle(.secondary)
        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 150), spacing: 6, alignment: .leading)],
          alignment: .leading, spacing: 6
        ) {
          ForEach(categories) { category in
            cell(category)
          }
        }
      }
      .padding(.top, 8)
    } label: {
      HStack(spacing: 6) {
        Text("Saved +20 coverage by slot and main stat").font(.callout)
        Text("\(sparse) of \(categories.count) groups sparse").font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func cell(_ category: InventoryCategory) -> some View {
    let highlighted = current?.slot == category.slot && current?.main == category.main
    return HStack(spacing: 6) {
      Text("\(category.slot.label) · \(category.main.label)").lineLimit(1)
        .minimumScaleFactor(0.8)
      Spacer(minLength: 2)
      Text(String(category.count)).monospacedDigit().bold()
        .foregroundStyle(category.count >= 3 ? Theme.accent : .secondary)
    }
    .font(.caption)
    .padding(.horizontal, 8).padding(.vertical, 5)
    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(highlighted ? Theme.accent.opacity(0.7) : .clear)
    }
    .help(
      category.count == 0
        ? "None saved" : category.count < 3 ? "Sparse: under 3 saved" : "3+ saved")
  }
}
