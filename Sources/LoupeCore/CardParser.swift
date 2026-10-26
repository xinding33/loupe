import Foundation

public enum CardParser {
  public static func parse(_ text: String, fiveStarsConfirmed: Bool, rule: RollRule = .ordinary)
    throws -> Artifact
  {
    guard fiveStarsConfirmed else {
      throw ArtifactError("Confirm a five-star artifact. Other rarities are not supported.")
    }
    let card = try layout(text)
    let special = ["sanctifying", "guaranteed", "reshap", "defined affix"].contains {
      text.localizedCaseInsensitiveContains($0)
    }
    return try Artifact(
      setName: card.setName, slot: card.slot, main: card.main, level: card.level,
      substats: card.substats, unactivated: card.unactivated, rule: special ? .special : rule)
  }

  /// Indices of the newline-separated lines that `parse` reads, or nil when it cannot place them.
  /// Only these lines should decide OCR confidence: Vision reads decorations such as the
  /// rarity stars as low-confidence text.
  public static func parsedLines(_ text: String) -> [Int]? { try? layout(text).used }

  /// Replaces Cyrillic and Greek capitals and lowercase letters that Vision returns for their
  /// Latin look-alikes, such as the Cyrillic Р in "HР".
  public static func latinized(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.map { lookalikes[$0] ?? $0 }))
  }

  /// Latinizes a line and trims the bullets, sparkles and stray dots Vision reads at its ends,
  /// as in "•15.2%" or "Serenade:(4) *". Keeps "+", "%", "(" and ":", which carry meaning.
  public static func tidied(_ line: String) -> String {
    latinized(line).trimmingCharacters(
      in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "•·*.,-_'\"`~")))
  }

  private static let lookalikes: [Unicode.Scalar: Unicode.Scalar] = {
    let pairs: [(String, String)] = [
      ("АВЕКМНОРСТХУІЅЈ", "ABEKMHOPCTXYISJ"), ("аеорсухіјѕ", "aeopcyxijs"),
      ("ΑΒΕΖΗΙΚΜΝΟΡΤΥΧ", "ABEZHIKMNOPTYX"), ("ο", "o"),
    ]
    var map: [Unicode.Scalar: Unicode.Scalar] = [:]
    for (from, to) in pairs {
      for (a, b) in zip(from.unicodeScalars, to.unicodeScalars) { map[a] = b }
    }
    return map
  }()

  private struct Layout {
    var slot: Slot
    var level: Int
    var main: Stat
    var substats: [Substat] = []
    var unactivated: Substat?
    var setName = ""
    var used: [Int]
  }

  private static func layout(_ text: String) throws -> Layout {
    let lines = text.components(separatedBy: .newlines).map(tidied)
    let filled = lines.indices.filter { !lines[$0].isEmpty }
    let slots: [(String, Slot)] = [
      ("Flower of Life", .flower), ("Plume of Death", .plume), ("Sands of Eon", .sands),
      ("Goblet of Eonothem", .goblet), ("Circlet of Logos", .circlet),
    ]
    guard
      let slotLine = filled.first(where: { line in
        slots.contains { lines[line].localizedCaseInsensitiveContains($0.0) }
      }),
      let slot = slots.first(where: { lines[slotLine].localizedCaseInsensitiveContains($0.0) })?.1
    else {
      throw ArtifactError(
        "No artifact card found. Open a piece in Inventory, or paste its card text.")
    }
    guard
      let levelLine = filled.first(where: {
        $0 > slotLine && lines[$0].range(of: #"^\+\s*\d{1,2}$"#, options: .regularExpression) != nil
      }),
      let level = Int(lines[levelLine].filter(\.isNumber))
    else {
      throw ArtifactError("Cannot read the artifact level. Keep the full card visible.")
    }
    let header = filled.filter { $0 > slotLine && $0 < levelLine }
    let mainLine = header.first(where: { identifyStat(lines[$0], hasPercent: false) != nil })
    // A flower or plume has only one main stat, so its label can be lost to the background.
    let fixedMain: Stat? = slot == .flower ? .hp : slot == .plume ? .atk : nil
    guard
      let main = mainLine.flatMap({
        identifyStat(lines[$0], hasPercent: header.contains { lines[$0].contains("%") })
      }) ?? fixedMain
    else {
      throw ArtifactError("Cannot read the main stat.")
    }
    var card = Layout(
      slot: slot, level: level, main: main,
      used: [slotLine] + (mainLine.map { [$0] } ?? [])
        + header.filter { lines[$0].contains(where: \.isNumber) } + [levelLine])
    for (position, index) in filled.enumerated() where index > levelLine {
      let line = lines[index]
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
        // The character screen's narrower card wraps "(unactivated)" onto its own line.
        let wrapped = filled.dropFirst(position + 1).first.flatMap {
          marksUnactivated(lines[$0]) && !lines[$0].contains(where: \.isNumber) ? $0 : nil
        }
        if marksUnactivated(line) || wrapped != nil {
          guard card.unactivated == nil else {
            throw ArtifactError("Multiple unactivated lines. Read one card at a time.")
          }
          card.unactivated = stat
        } else {
          card.substats.append(stat)
        }
        card.used += [index] + (wrapped.map { [$0] } ?? [])
      } else if !card.substats.isEmpty,
        // The character screen adds the equipped count: "Set Name: (4)".
        let colon = line.range(of: #":\s*(\(\d\))?$"#, options: .regularExpression)
      {
        card.setName = line[..<colon.lowerBound]
          .folding(options: .diacriticInsensitive, locale: nil)
          .trimmingCharacters(
            in: .whitespaces.union(.punctuationCharacters).union(.symbols))
        card.used.append(index)
        return card
      } else if line.contains(where: \.isNumber) {
        // Only substats carry numbers here; skipping one would read a four-stat card as three.
        throw ArtifactError("Cannot read a substat line. Correct the card text.")
      }
    }
    throw ArtifactError("Cannot read the set name. Include the line above the set bonuses.")
  }

  /// Vision can drop the parenthesis or misread letters inside the marker, as in "(unagtivated)".
  private static func marksUnactivated(_ line: String) -> Bool {
    line.range(
      of: #"\(\s*un\w{4,}|un\w*vated|activated"#, options: [.regularExpression, .caseInsensitive])
      != nil
  }

  static func identifyStat(_ text: String, hasPercent: Bool) -> Stat? {
    // Bullets and background sparkles read as stray marks in and around the label
    // ("Elemental-Mastery", "CRIT, Rate"), and Vision sometimes adds diacritics ("Mästery").
    let cleaned = text.replacingOccurrences(of: "%", with: "")
      .folding(options: .diacriticInsensitive, locale: nil)
      .components(
        separatedBy: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols)
      )
      .filter { !$0.isEmpty }.joined(separator: " ").lowercased()
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
    // Both readings come from the screen, where the game keeps substat order, so labels read in
    // swapped rows cannot pass. Saved records may come from imports in another order.
    func keys(_ artifact: Artifact) -> [Stat] {
      (artifact.substats + (artifact.unactivated.map { [$0] } ?? [])).map(\.key)
    }
    guard keys(candidate) == keys(previous) else {
      throw ArtifactError("Enhance stats are in a different order. Waiting for a clear frame.")
    }
    return try previous.upgraded(to: candidate)
  }
}
