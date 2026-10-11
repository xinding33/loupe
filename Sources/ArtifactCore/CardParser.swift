import Foundation

public enum CardParser {
  public static func parse(_ text: String, fiveStarsConfirmed: Bool, rule: RollRule = .ordinary)
    throws -> Artifact
  {
    guard fiveStarsConfirmed else {
      throw ArtifactError("Confirm a five-star artifact. Other rarities are not supported.")
    }
    let lines = text.components(separatedBy: .newlines).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    let slots: [(String, Slot)] = [
      ("Flower of Life", .flower), ("Plume of Death", .plume), ("Sands of Eon", .sands),
      ("Goblet of Eonothem", .goblet), ("Circlet of Logos", .circlet),
    ]
    guard
      let slotLine = lines.firstIndex(where: { line in
        slots.contains { line.localizedCaseInsensitiveContains($0.0) }
      }),
      let slot = slots.first(where: { lines[slotLine].localizedCaseInsensitiveContains($0.0) })?.1
    else {
      throw ArtifactError(
        "No artifact card found. Open a piece in Inventory, or paste its card text.")
    }
    guard
      let levelLine = lines.indices.first(where: {
        $0 > slotLine && lines[$0].range(of: #"^\+\s*\d{1,2}$"#, options: .regularExpression) != nil
      }),
      let level = Int(lines[levelLine].filter(\.isNumber))
    else {
      throw ArtifactError("Cannot read the artifact level. Keep the full card visible.")
    }
    let header = lines[(slotLine + 1)..<levelLine]
    guard let mainLine = header.first(where: { identifyStat($0, hasPercent: false) != nil }),
      let main = identifyStat(mainLine, hasPercent: header.contains { $0.contains("%") })
    else {
      throw ArtifactError("Cannot read the main stat.")
    }
    var substats: [Substat] = []
    var unactivated: Substat?
    var setName: String?
    for line in lines.dropFirst(levelLine + 1) {
      if line.localizedCaseInsensitiveContains("2-Piece")
        || line.localizedCaseInsensitiveContains("2 Piece")
      {
        break
      }
      if let plus = line.firstIndex(of: "+"),
        let key = identifyStat(String(line[..<plus]), hasPercent: line.contains("%"))
      {
        let tail = String(line[line.index(after: plus)...]).replacingOccurrences(of: ",", with: "")
        guard let range = tail.range(of: #"^\s*\d+(?:\.\d+)?"#, options: .regularExpression),
          let value = Double(tail[range].trimmingCharacters(in: .whitespaces))
        else {
          throw ArtifactError("Cannot read \(key.label). Correct the card text.")
        }
        let stat = Substat(key, value)
        if line.localizedCaseInsensitiveContains("unactivated") {
          guard unactivated == nil else {
            throw ArtifactError("Multiple unactivated lines. Read one card at a time.")
          }
          unactivated = stat
        } else {
          substats.append(stat)
        }
      } else if line.hasSuffix(":"), !substats.isEmpty {
        setName = String(line.dropLast())
        break
      }
    }
    guard let setName else {
      throw ArtifactError("Cannot read the set name. Include the line above the set bonuses.")
    }
    let special = ["sanctifying", "guaranteed", "reshap", "defined affix"].contains {
      text.localizedCaseInsensitiveContains($0)
    }
    return try Artifact(
      setName: setName, slot: slot, main: main, level: level, substats: substats,
      unactivated: unactivated, rule: special ? .special : rule)
  }

  static func identifyStat(_ text: String, hasPercent: Bool) -> Stat? {
    let cleaned = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(
      in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "•·-"))
    ).lowercased()
    for stat in Stat.allCases where stat != .hpPercent && stat != .atkPercent && stat != .defPercent
    {
      if cleaned == stat.label.lowercased() || cleaned.hasPrefix(stat.label.lowercased() + " ") {
        if hasPercent {
          if stat == .hp { return .hpPercent }
          if stat == .atk { return .atkPercent }
          if stat == .def { return .defPercent }
        }
        return stat
      }
    }
    return nil
  }

  public static func parseEnhancement(_ text: String, previous: Artifact, pieceName: String) throws
    -> Artifact
  {
    let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
    guard let heading = lines.first, let slash = heading.firstIndex(of: "/"),
      Artifact.normalizeSet(String(heading[heading.index(after: slash)...]))
        == Artifact.normalizeSet(pieceName),
      let levelLine = lines.dropFirst().first,
      levelLine.range(of: #"^\+\d{1,2}$"#, options: .regularExpression) != nil,
      let mainRow = lines.dropFirst(2).first,
      let plus = mainRow.firstIndex(of: "+")
    else {
      throw ArtifactError(
        "Enhance does not match the last verified Inventory card. Return to Inventory first.")
    }
    let slotText = heading[..<slash].trimmingCharacters(in: .whitespaces)
    let mainText = String(mainRow[..<plus])
    let mainValue = String(mainRow[mainRow.index(after: plus)...])
    let canonical =
      ([pieceName, slotText, mainText, mainValue, levelLine] + Array(lines.dropFirst(3)) + [
        previous.setName + ":"
      ]).joined(separator: "\n")
    let candidate = try parse(canonical, fiveStarsConfirmed: true, rule: previous.rule)
    return try previous.upgraded(to: candidate)
  }
}
