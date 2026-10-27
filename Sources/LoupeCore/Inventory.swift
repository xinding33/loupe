import Foundation

public struct Inventory: Codable, Sendable {
  public private(set) var artifacts: [Artifact] = []
  public init() {}
  @discardableResult public mutating func save(
    _ artifact: Artifact, allowIdenticalCopy: Bool = false
  ) -> UUID {
    if !allowIdenticalCopy,
      let existing = artifacts.first(where: { $0.signature == artifact.signature })
    {
      return existing.id
    }
    artifacts.append(artifact)
    return artifact.id
  }
  public mutating func update(_ id: UUID, with artifact: Artifact) throws {
    guard let index = artifacts.firstIndex(where: { $0.id == id }) else {
      throw ArtifactError("The linked artifact is no longer in the inventory.")
    }
    artifacts[index] = try artifacts[index].upgraded(to: artifact)
  }
  public mutating func remove(_ id: UUID) { artifacts.removeAll { $0.id == id } }

  public mutating func merge(_ incoming: [Artifact]) throws {
    var available = Dictionary(grouping: artifacts, by: \.signature).mapValues(\.count)
    for artifact in incoming {
      if available[artifact.signature, default: 0] > 0 {
        available[artifact.signature, default: 0] -= 1
      } else {
        artifacts.append(try artifact.withID(UUID()))
      }
    }
  }

  public func write(to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: url, options: .atomic)
  }
  public static func read(from url: URL) throws -> Inventory {
    let inventory = try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: url))
    guard Set(inventory.artifacts.map(\.id)).count == inventory.artifacts.count else {
      throw ArtifactError("Inventory contains duplicate IDs.")
    }
    return inventory
  }

  public static func importGOOD(_ data: Data) throws -> (artifacts: [Artifact], skipped: Int) {
    struct GOOD: Decodable {
      let format: String
      let artifacts: [Item]
    }
    struct Item: Decodable {
      let setKey: String
      let slotKey: Slot
      let mainStatKey: Stat
      let level: Int
      let rarity: Int
      let substats: [Substat]
      let unactivatedSubstats: [Substat]?
    }
    let file = try JSONDecoder().decode(GOOD.self, from: data)
    guard file.format == "GOOD" else {
      throw ArtifactError("Choose a GOOD-format inventory export.")
    }
    let supported = file.artifacts.filter { $0.rarity == 5 || $0.rarity == 4 }
    let artifacts = try supported.enumerated().map { index, item in
      guard (item.unactivatedSubstats?.count ?? 0) <= 1 else {
        throw ArtifactError("GOOD artifact \(index + 1) has multiple unactivated stats.")
      }
      do {
        return try Artifact(
          setName: item.setKey, slot: item.slotKey, main: item.mainStatKey, level: item.level,
          substats: item.substats.filter { $0.value > 0 },
          unactivated: item.unactivatedSubstats?.first,
          rule: item.level == Artifact.maxLevel(item.rarity) ? .ordinary : .special,
          rarity: item.rarity)
      } catch { throw ArtifactError("GOOD artifact \(index + 1): \(error.localizedDescription)") }
    }
    return (artifacts, file.artifacts.count - supported.count)
  }
}
