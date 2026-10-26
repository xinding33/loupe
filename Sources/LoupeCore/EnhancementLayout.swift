import CoreGraphics
import Foundation

public struct TextRegion: Sendable {
  public let text: String
  public let bounds: CGRect
  public let confidence: Float

  public init(text: String, bounds: CGRect, confidence: Float) {
    self.text = text
    self.bounds = bounds
    self.confidence = confidence
  }
}

public enum EnhancementLayout {
  public static func normalized(_ observations: [TextRegion]) -> [TextRegion] {
    let statNames = Set(Stat.allCases.map { $0.label.replacingOccurrences(of: "%", with: "") })
    return joinedWrappedLabels(observations, statNames: statNames).compactMap { observation in
      let text = CardParser.latinized(
        observation.text.folding(
          options: .diacriticInsensitive, locale: Locale(identifier: "en_US")))
      let clean: String
      if let level = cleanNumber(text, level: true), observation.bounds.minX > 0.5 {
        clean = level
      } else if observation.bounds.minX > 0.8, let value = cleanNumber(text) {
        clean = value
      } else if observation.bounds.minX > 0.5, observation.bounds.minX < 0.8,
        !text.contains(where: \.isNumber)
      {
        let words = text.components(separatedBy: CharacterSet.letters.inverted).filter {
          !$0.isEmpty
        }.joined(separator: " ")
        if words.lowercased() == "unactivated" {
          clean = "(unactivated)"
        } else if let stat = statNames.first(where: { words == $0 || words == $0 + " unactivated" })
        {
          clean = stat + (words.hasSuffix(" unactivated") ? " (unactivated)" : "")
        } else {
          return nil
        }
      } else {
        return nil
      }
      return TextRegion(text: clean, bounds: observation.bounds, confidence: observation.confidence)
    }
  }

  /// The Enhance panel wraps a long main-stat label such as "Elemental Mastery" onto two lines,
  /// which Vision returns as separate observations.
  private static func joinedWrappedLabels(_ observations: [TextRegion], statNames: Set<String>)
    -> [TextRegion]
  {
    func words(_ region: TextRegion) -> String {
      CardParser.latinized(region.text).components(separatedBy: CharacterSet.letters.inverted)
        .filter { !$0.isEmpty }.joined(separator: " ")
    }
    func isLabel(_ region: TextRegion) -> Bool {
      region.bounds.minX > 0.5 && region.bounds.minX < 0.8
        && !region.text.contains(where: \.isNumber) && !words(region).isEmpty
    }
    var result = observations
    for upper in observations where isLabel(upper) {
      guard
        let lower = observations.first(where: { lower in
          isLabel(lower) && lower.bounds != upper.bounds
            && abs(lower.bounds.minX - upper.bounds.minX) < 0.02
            && upper.bounds.minY - lower.bounds.maxY > -0.005
            && upper.bounds.minY - lower.bounds.maxY < max(upper.bounds.height, lower.bounds.height)
            && statNames.contains(words(upper) + " " + words(lower))
        }),
        result.contains(where: { $0.bounds == upper.bounds }),
        result.contains(where: { $0.bounds == lower.bounds })
      else { continue }
      result.removeAll { $0.bounds == upper.bounds || $0.bounds == lower.bounds }
      result.append(
        TextRegion(
          text: words(upper) + " " + words(lower), bounds: upper.bounds.union(lower.bounds),
          confidence: min(upper.confidence, lower.confidence)))
    }
    return result
  }

  public static func assemble(_ observations: [TextRegion], heading: TextRegion) throws -> (
    text: String, confidence: Float
  ) {
    let observations = normalized(observations)
    guard
      let level = observations.first(where: {
        $0.bounds.minX > 0.5
          && cleanNumber($0.text, level: true) != nil
      }), let levelText = cleanNumber(level.text, level: true)
    else { throw ArtifactError("Waiting for the Enhance level to settle.") }
    let area = observations.filter {
      $0.bounds.minX > 0.5 && $0.bounds.maxY < level.bounds.minY
        && $0.bounds.minY > level.bounds.minY - 0.36
    }
    let statNames = Set(Stat.allCases.map { $0.label.replacingOccurrences(of: "%", with: "") })
    let labels = area.compactMap { observation -> (region: TextRegion, name: String)? in
      guard observation.bounds.minX < 0.8, !observation.text.contains(where: \.isNumber) else {
        return nil
      }
      let clean = observation.text.components(separatedBy: CharacterSet.letters.inverted)
        .filter { !$0.isEmpty }.joined(separator: " ")
      guard let name = statNames.first(where: { clean == $0 || clean == $0 + " unactivated" })
      else {
        return nil
      }
      return (observation, name)
    }.sorted { $0.region.bounds.midY > $1.region.bounds.midY }
    let values = area.compactMap { observation -> TextRegion? in
      guard observation.bounds.minX > 0.8, let text = cleanNumber(observation.text) else {
        return nil
      }
      return TextRegion(text: text, bounds: observation.bounds, confidence: observation.confidence)
    }.sorted { $0.bounds.midY > $1.bounds.midY }
    guard labels.count == 5, values.count == 5 else {
      throw ArtifactError(
        "Enhance: read \(labels.count)/5 stat labels and \(values.count)/5 values. Table text: \(area.map(\.text).joined(separator: "; "))."
      )
    }
    var rows: [String] = []
    var confidence = min(level.confidence, heading.confidence)
    // Match ordered columns together; wrapped inactive labels can overlap a neighboring row's OCR box.
    for (label, value) in zip(labels, values) {
      guard abs(label.region.bounds.midY - value.bounds.midY) < 0.04 else {
        throw ArtifactError(
          "Enhance: \(label.name) and its value are not aligned. Waiting for a clear frame.")
      }
      let inactive =
        label.region.text.localizedCaseInsensitiveContains("unactivated")
        || area.contains { notice in
          guard
            notice.text.trimmingCharacters(
              in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "()"))
            ).lowercased() == "unactivated"
          else { return false }
          let owner = labels.filter { $0.region.bounds.midY >= notice.bounds.midY }
            .min {
              $0.region.bounds.midY - notice.bounds.midY < $1.region.bounds.midY
                - notice.bounds.midY
            }
          return owner?.region.bounds == label.region.bounds
            && label.region.bounds.midY - notice.bounds.midY < 0.045
        }
      rows.append(label.name + "+" + value.text + (inactive ? " (unactivated)" : ""))
      // Labels must name a stat and match the verified card's stats, so only values count here.
      confidence = min(confidence, value.confidence)
    }
    return (([heading.text, levelText] + rows).joined(separator: "\n"), confidence)
  }

  private static func cleanNumber(_ text: String, level: Bool = false) -> String? {
    // Remove decoration only at token edges; never infer digits or repair an internal decimal.
    let edges = CharacterSet.whitespacesAndNewlines
      .union(.punctuationCharacters).union(.symbols)
      .subtracting(CharacterSet(charactersIn: level ? "+.,%" : ".,%"))
    let clean = text.trimmingCharacters(in: edges)
    let pattern = level ? #"^\+\d{1,2}$"# : #"^\d+(?:,\d{3})*(?:\.\d+)?%?$"#
    return clean.range(of: pattern, options: .regularExpression) == nil ? nil : clean
  }
}
