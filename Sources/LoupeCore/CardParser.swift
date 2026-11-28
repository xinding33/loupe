import Foundation

public enum CardParser {
  public static func parse(_ text: String, fiveStarsConfirmed: Bool, rule: RollRule = .ordinary)
    throws -> Artifact
  {
    try parse(text, stars: fiveStarsConfirmed ? 5 : 0, rule: rule)
  }

  /// Parses a card with the number of rarity stars counted on it: four or five.
  public static func parse(_ text: String, stars: Int, rule: RollRule = .ordinary) throws
    -> Artifact
  {
    guard stars == 4 || stars == 5 else {
      throw ArtifactError(
        "Confirm a four- or five-star artifact. Other rarities are not supported.")
    }
    let card = try layout(text)
    let special = ["sanctifying", "guaranteed", "reshap", "defined affix"].contains {
      text.localizedCaseInsensitiveContains($0)
    }
    return try Artifact(
      setName: card.setName, slot: card.slot, main: card.main, level: card.level,
      substats: card.substats, unactivated: card.unactivated, rule: special ? .special : rule,
      rarity: stars)
  }

  /// A card of any rarity, by the stats it shows and its level, for telling one card from the
  /// next without parsing it as a piece Loupe grades. Nil when no card can be placed, or when
  /// its level is past what `stars` allow, so the stars were miscounted. A one-star piece
  /// starts with no substats, so none are needed here.
  public static func glance(_ text: String, stars: Int) -> (key: String, level: Int)? {
    let maximum = [1: 4, 2: 4, 3: 12, 4: 16, 5: 20][stars] ?? -1
    guard let card = try? layout(text, substatsRequired: false), card.level <= maximum else {
      return nil
    }
    let stats = (card.substats + (card.unactivated.map { [$0] } ?? [])).map {
      "\($0.key.rawValue)=\($0.value)"
    }
    // Names keep only letters and digits, so a curly apostrophe read in one frame and a straight
    // one in the next don't make two cards.
    let names = [pieceName(text), card.setName].map {
      String($0.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }
    let key = names + [card.slot.rawValue, card.main.rawValue, "+\(card.level)"] + stats
    return (key.joined(separator: "|"), card.level)
  }

  /// A card read by an inventory scan, where nobody confirms the stars or the level. Parsed
  /// with the stars counted, four or five, then the other: the count can be off, and the
  /// rolls decide, since a four-star's are four fifths of a five-star's. A card that fits both
  /// is taken as counted, or not at all when the count was neither. A card that doesn't parse
  /// at the level read on it is tried at `label`, the level read under its tile, which its
  /// rolls must fit. `note` says what was taken from elsewhere.
  public static func parseScanned(_ text: String, stars counted: Int, label: Int?) throws -> (
    artifact: Artifact, note: String
  ) {
    func parsed(_ stars: Int) -> (Artifact, String)? {
      if let artifact = try? parse(text, stars: stars) { return (artifact, "") }
      guard let label, let relabelled = withLevel(text, label),
        let artifact = try? parse(relabelled, stars: stars)
      else { return nil }
      return (artifact, "level taken from the tile")
    }
    let order = counted == 4 ? [4, 5] : [5, 4]
    let fits = order.compactMap { stars in parsed(stars).map { (stars, $0.0, $0.1) } }
    guard
      let (stars, artifact, note) = fits.count == 1
        ? fits.first : fits.first(where: { $0.0 == counted })
    else {
      if fits.count == 2 { throw ArtifactError("The card fits four and five stars.") }
      // Why it fails as the likelier rarity.
      _ = try parse(text, stars: order[0])
      throw ArtifactError("The card doesn't parse.")
    }
    let recount = stars == counted ? "" : "\(stars) stars, \(counted) counted"
    return (artifact, [note, recount].filter { !$0.isEmpty }.joined(separator: "; "))
  }

  /// `text` with its level line, the first "+N" line after the slot, set to `level`: for a card
  /// whose level Vision misread, as "+16" for "+10", where the level is known from elsewhere.
  /// Nil when there's no level line or it already says `level`.
  public static func withLevel(_ text: String, _ level: Int) -> String? {
    var lines = text.components(separatedBy: .newlines)
    guard
      let slot = lines.firstIndex(where: { line in
        slotNames.contains { tidied(line).localizedCaseInsensitiveContains($0.0) }
      }),
      let index = lines.indices.first(where: {
        $0 > slot
          && tidied(lines[$0]).range(of: #"^\+\s*\d{1,2}$"#, options: .regularExpression) != nil
      }),
      Int(lines[index].filter(\.isNumber)) != level
    else { return nil }
    lines[index] = "+\(level)"
    return lines.joined(separator: "\n")
  }

  /// Indices of the newline-separated lines that `parse` reads, or nil when it cannot place them.
  /// Only these lines should decide OCR confidence: Vision reads decorations such as the
  /// rarity stars as low-confidence text.
  public static func parsedLines(_ text: String) -> [Int]? { try? layout(text).used }

  /// The piece name above the slot line. The character screen wraps long names, as in
  /// "Crystal Tear of the" / "Wanderer", and Enhance compares against the whole name.
  public static func pieceName(_ text: String) -> String {
    let lines = text.components(separatedBy: .newlines).map(tidied).filter { !$0.isEmpty }
    guard
      let slot = lines.firstIndex(where: { line in
        slotNames.contains { line.localizedCaseInsensitiveContains($0.0) }
      })
    else { return lines.first ?? "" }
    return lines[..<slot].joined(separator: " ")
  }

  /// Replaces Cyrillic and Greek capitals and lowercase letters that Vision returns for their
  /// Latin look-alikes, such as the Cyrillic Р in "HР".
  public static func latinized(_ text: String) -> String {
    String(String.UnicodeScalarView(text.unicodeScalars.map { lookalikes[$0] ?? $0 }))
  }

  /// Latinizes a line and trims the bullets, sparkles and stray dots Vision reads at its ends,
  /// as in "•15.2%" or "Serenade:(4) *". Keeps "+", "%", "(" and ":", which carry meaning.
  public static func tidied(_ line: String) -> String {
    // Vision also returns a noncharacter, U+FFFE, for some bullets.
    latinized(line).trimmingCharacters(
      in: .whitespacesAndNewlines.union(.illegalCharacters).union(.controlCharacters)
        .union(CharacterSet(charactersIn: "•·*.,-_'\"`~\u{FFFD}\u{FFFE}\u{FFFF}")))
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

  private static let slotNames: [(String, Slot)] = [
    ("Flower of Life", .flower), ("Plume of Death", .plume), ("Sands of Eon", .sands),
    ("Goblet of Eonothem", .goblet), ("Circlet of Logos", .circlet),
  ]

  private struct Layout {
    var slot: Slot
    var level: Int
    var main: Stat
    var substats: [Substat] = []
    var unactivated: Substat?
    var setName = ""
    var used: [Int]
  }

  private static func layout(_ text: String, substatsRequired: Bool = true) throws -> Layout {
    let lines = text.components(separatedBy: .newlines).map(tidied)
    let filled = lines.indices.filter { !lines[$0].isEmpty }
    guard
      let slotLine = filled.first(where: { line in
        slotNames.contains { lines[line].localizedCaseInsensitiveContains($0.0) }
      }),
      let slot = slotNames.first(where: { lines[slotLine].localizedCaseInsensitiveContains($0.0) })?
        .1
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
      } else if !card.substats.isEmpty || !substatsRequired,
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

  /// Both names come from OCR. Sparkles add stray letters, and the character screen can add a
  /// button label above the name ("Recommendations Gladiator's Nostalgia"). Slot, main stat and
  /// substats must still agree, so allow those and up to two misread letters.
  public static func namesMatch(_ card: String, _ enhance: String) -> Bool {
    func key(_ name: String) -> [Character] {
      Array(Artifact.normalizeSet(name.folding(options: .diacriticInsensitive, locale: nil)))
    }
    let a = key(card)
    let b = key(enhance)
    guard b.count >= 6 else { return a == b }
    if a.suffix(b.count).elementsEqual(b) { return true }
    var row = Array(0...b.count)
    for (i, x) in a.enumerated() {
      var next = [i + 1]
      for (j, y) in b.enumerated() {
        next.append(min(row[j + 1] + 1, next[j] + 1, row[j] + (x == y ? 0 : 1)))
      }
      row = next
    }
    return row[b.count] <= 2
  }

  public static func parseEnhancement(_ text: String, previous: Artifact, pieceName: String) throws
    -> Artifact
  {
    let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
    guard let heading = lines.first, let slash = heading.firstIndex(of: "/"),
      namesMatch(pieceName, String(heading[heading.index(after: slash)...])),
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
    let candidate = try parse(canonical, stars: previous.rarity, rule: previous.rule)
    // Both readings come from the screen, where the game keeps substat order, so labels read in
    // swapped rows cannot pass. A four-star adds lines below the existing ones, and a missed row
    // cannot pass either. Saved records may come from imports in another order.
    func keys(_ artifact: Artifact) -> [Stat] {
      (artifact.substats + (artifact.unactivated.map { [$0] } ?? [])).map(\.key)
    }
    guard keys(candidate).starts(with: keys(previous)) else {
      throw ArtifactError("Enhance stats are in a different order. Waiting for a clear frame.")
    }
    return try previous.upgraded(to: candidate)
  }
}
