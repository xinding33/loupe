import Foundation

public struct FieldConfirmation {
  private struct Field {
    enum Kind { case heading, level, label, value, inactive }
    let kind: Kind
    let region: TextRegion

    func sharesPosition(with other: Field) -> Bool {
      guard kind == other.kind else { return false }
      if kind == .heading || kind == .level || kind == .inactive { return true }
      return abs(region.bounds.midY - other.region.bounds.midY) < 0.018
        && abs(region.bounds.minX - other.region.bounds.minX) < 0.04
    }
  }
  private var frames: [(time: TimeInterval, fields: [Field])] = []

  public init() {}

  public mutating func observe(_ regions: [TextRegion], heading: TextRegion?, at time: TimeInterval)
    throws -> (text: String, confidence: Float)
  {
    frames.removeAll { time - $0.time > 2 || time < $0.time }
    var fields = EnhancementLayout.normalized(regions).flatMap { region -> [Field] in
      if region.text == "(unactivated)" { return [Field(kind: .inactive, region: region)] }
      let kind: Field.Kind =
        region.text.hasPrefix("+") ? .level : region.bounds.minX > 0.8 ? .value : .label
      if region.text.hasSuffix(" (unactivated)") {
        return [
          Field(
            kind: .label,
            region: TextRegion(
              text: String(region.text.dropLast(" (unactivated)".count)), bounds: region.bounds,
              confidence: region.confidence)),
          Field(
            kind: .inactive,
            region: TextRegion(
              text: "(unactivated)", bounds: region.bounds, confidence: region.confidence)),
        ]
      }
      return [Field(kind: kind, region: region)]
    }
    if let heading {
      let slots = [
        "Flower of Life", "Plume of Death", "Sands of Eon", "Goblet of Eonothem",
        "Circlet of Logos",
      ]
      let folded = heading.text.folding(
        options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
      let parts = folded.split(separator: "/", maxSplits: 1).map(String.init)
      if parts.count == 2,
        let slot = slots.first(where: {
          Artifact.normalizeSet($0) == Artifact.normalizeSet(parts[0])
        })
      {
        let text = slot + " / " + Artifact.normalizeSet(parts[1])
        fields.append(
          Field(
            kind: .heading,
            region: TextRegion(text: text, bounds: heading.bounds, confidence: heading.confidence)))
      }
    }
    let level =
      fields.first { $0.kind == .level }
      ?? frames.reversed().flatMap(\.fields).first { $0.kind == .level }
    if let level {
      if let previous = frames.reversed().flatMap(\.fields).first(where: { $0.kind == .level }),
        previous.region.text != level.region.text
      {
        frames.removeAll()
      }
      fields.removeAll {
        $0.kind != .heading && $0.kind != .level
          && ($0.region.bounds.maxY >= level.region.bounds.minY
            || $0.region.bounds.minY <= level.region.bounds.minY - 0.36)
      }
    }
    for (index, field) in fields.enumerated() {
      if fields.dropFirst(index + 1).contains(where: {
        $0.sharesPosition(with: field) && $0.region.text != field.region.text
      }) {
        frames.removeAll()
        throw ArtifactError(
          "Multiple values occupy the same field. Close the comparison or preview.")
      }
    }
    frames.append((time, fields))
    if frames.count > 5 { frames.removeFirst() }
    var selected: [Field] = []
    for field in frames.reversed().flatMap(\.fields) {
      if selected.contains(where: { $0.sharesPosition(with: field) }) { continue }
      selected.append(field)
    }
    for field in selected {
      let votes = frames.filter { frame in
        frame.fields.contains {
          $0.sharesPosition(with: field) && $0.region.text == field.region.text
        }
      }.count
      guard votes >= 2 else {
        throw ArtifactError("Checking changed or unreadable artifact fields.")
      }
    }
    guard let title = selected.first(where: { $0.kind == .heading }) else {
      throw ArtifactError("Waiting for the artifact title.")
    }
    return try EnhancementLayout.assemble(
      selected.filter { $0.kind != .heading }.map(\.region), heading: title.region)
  }
}
