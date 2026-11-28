import Foundation

/// Every build, release or development and old or new, reads and writes the same file, so each
/// keeps what it doesn't understand: a record it can't read is kept as it was, and fields it
/// doesn't know stay on the records it saves again.
public struct Inventory: Codable, Sendable {
  public private(set) var artifacts: [Artifact] = []
  /// Saved records this build can't read, from a newer build or damaged by hand, written back
  /// unchanged after the others.
  public private(set) var unreadable: [JSONValue] = []
  /// Each readable record as it was read, so one this build hasn't changed is written back
  /// exactly, nested fields it doesn't know included, and a changed one keeps its unknown fields.
  private var asRead: [UUID: ReadRecord] = [:]
  /// Top-level fields this build doesn't know.
  private var unknownTopLevel: [String: JSONValue] = [:]
  public init() {}
  @discardableResult public mutating func save(
    _ artifact: Artifact, allowIdenticalCopy: Bool = false
  ) -> UUID {
    if !allowIdenticalCopy,
      let existing = artifacts.first(where: { $0.identity == artifact.identity })
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
  public mutating func remove(_ id: UUID) {
    artifacts.removeAll { $0.id == id }
    asRead[id] = nil
  }

  public mutating func merge(_ incoming: [Artifact]) throws {
    var available = Dictionary(grouping: artifacts, by: \.identity).mapValues(\.count)
    for artifact in incoming {
      if available[artifact.identity, default: 0] > 0 {
        available[artifact.identity, default: 0] -= 1
      } else {
        artifacts.append(try artifact.withID(UUID()))
      }
    }
  }

  /// Adds the pieces a sweep of the in-game Inventory read, `seen`, where each card is one real
  /// piece, so two identical cards are two copies.
  ///
  /// A card saved as often as it was seen is already saved; one seen more often adds the copies
  /// missing. Cards match whatever their roll rule, which a GOOD import sets differently. A new
  /// piece replaces a saved lower-level record it could have been levelled from, when that
  /// record is gone from the game and is the only one it could be, and no other new piece could
  /// have come from it. A record is gone when the sweep covered its level (one of `covered`)
  /// without seeing it. Nothing is deleted: records that are gone and
  /// weren't replaced are listed in `unseen`, and a new piece with more than one possible
  /// earlier record is added and listed with them in `ambiguous`.
  @discardableResult public mutating func mergeSweep(
    _ seen: [Artifact], covered: Set<Int>
  ) -> SweepMerge {
    var result = SweepMerge(read: seen.count)
    var accounted = Set<UUID>()
    var arrivals: [Artifact] = []
    let saved = Dictionary(grouping: artifacts, by: \.cardKey)
    for (key, copies) in Dictionary(grouping: seen, by: \.cardKey) {
      let matches = (saved[key] ?? []).prefix(copies.count)
      accounted.formUnion(matches.map(\.id))
      result.alreadySaved += matches.count
      arrivals += copies.dropFirst(matches.count)
    }
    // Keep list order among the arrivals.
    let order = Dictionary(seen.enumerated().map { ($1.id, $0) }, uniquingKeysWith: min)
    arrivals.sort { order[$0.id, default: 0] < order[$1.id, default: 0] }

    let rarities = Set(seen.map(\.rarity))
    let sets = Set(seen.map(\.setKey))
    let gone = artifacts.filter { artifact in
      !accounted.contains(artifact.id) && covered.contains(artifact.level)
    }
    var candidates = arrivals.map { arrival in
      gone.filter { Self.couldBecome($0, arrival) }.map(\.id)
    }
    // Pair a new piece and an earlier record when each is the other's only choice, and again
    // as pairing narrows the rest.
    var pairs: [Int: UUID] = [:]
    var changed = true
    while changed {
      changed = false
      let claims = Dictionary(
        candidates.enumerated().filter { pairs[$0.offset] == nil }.flatMap { $0.element }.map {
          ($0, 1)
        }, uniquingKeysWith: +)
      for index in candidates.indices where pairs[index] == nil {
        guard candidates[index].count == 1, let record = candidates[index].first,
          claims[record] == 1
        else { continue }
        pairs[index] = record
        for other in candidates.indices where other != index {
          candidates[other].removeAll { $0 == record }
        }
        changed = true
      }
    }

    var involved = Set(pairs.values)
    for (index, arrival) in arrivals.enumerated() {
      // The saved record's roll rule stands: a crafted piece levelled is still crafted.
      if let record = pairs[index], let position = artifacts.firstIndex(where: { $0.id == record }),
        let upgraded = try? Artifact(
          id: record, setName: arrival.setName, slot: arrival.slot, main: arrival.main,
          level: arrival.level, substats: arrival.substats, unactivated: arrival.unactivated,
          rule: artifacts[position].rule, rarity: arrival.rarity)
      {
        artifacts[position] = upgraded
        result.replaced.append(record)
        continue
      }
      let added = (try? arrival.withID(UUID())) ?? arrival
      artifacts.append(added)
      result.added.append(added.id)
      if !candidates[index].isEmpty {
        result.ambiguous.append(.init(added: added.id, earlier: candidates[index]))
        involved.formUnion(candidates[index])
      }
    }
    result.unseen =
      gone
      .filter {
        !involved.contains($0.id) && rarities.contains($0.rarity) && sets.contains($0.setKey)
      }
      .map(\.id)
    return result
  }

  /// Whether levelling `earlier` could have made `later`. The roll rule is set aside: a card
  /// read live and an imported record can disagree on it.
  static func couldBecome(_ earlier: Artifact, _ later: Artifact) -> Bool {
    guard earlier.level < later.level, earlier.setKey == later.setKey,
      let comparable = try? Artifact(
        id: earlier.id, setName: earlier.setName, slot: earlier.slot, main: earlier.main,
        level: earlier.level, substats: earlier.substats, unactivated: earlier.unactivated,
        rule: later.rule, rarity: earlier.rarity)
    else { return false }
    return (try? comparable.upgraded(to: later)) != nil
  }

  /// The file's contents.
  public func encoded() throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(self)
  }
  public func write(to url: URL) throws {
    try encoded().write(to: url, options: .atomic)
  }
  public static func read(from url: URL) throws -> Inventory {
    try read(Data(contentsOf: url))
  }
  /// Throws only for data that isn't an inventory at all, or whose records share an ID, readable
  /// or not, since a build that reads them all would refuse the file. Records that don't read
  /// are kept in `unreadable`.
  public static func read(_ data: Data) throws -> Inventory {
    let inventory = try JSONDecoder().decode(Inventory.self, from: data)
    let ids =
      inventory.artifacts.map(\.id.uuidString)
      + inventory.unreadable.compactMap { record -> String? in
        guard case .object(let fields) = record, case .string(let id) = fields["id"] else {
          return nil
        }
        return UUID(uuidString: id)?.uuidString
      }
    guard Set(ids).count == ids.count else {
      throw ArtifactError("Inventory contains duplicate IDs.")
    }
    return inventory
  }

  private static let artifactsKey = JSONValue.Key("artifacts")
  private static let artifactFields = Set(
    [
      Artifact.CodingKeys.id, .setName, .slot, .main, .level, .substats, .unactivated, .rule,
      .rarity,
    ].map(\.stringValue))

  /// One saved record: the artifact when this build can read it, and the JSON as it was.
  private struct Record: Decodable {
    let artifact: Artifact?
    let json: JSONValue
    init(from decoder: Decoder) throws {
      json = try JSONValue(from: decoder)
      artifact = try? Artifact(from: decoder)
    }
  }

  private struct ReadRecord: Sendable {
    let artifact: Artifact
    let fields: [String: JSONValue]
  }

  /// An artifact with the fields it was read with that this build doesn't know.
  private struct Stored: Encodable {
    let artifact: Artifact
    let unknown: [String: JSONValue]
    func encode(to encoder: Encoder) throws {
      try artifact.encode(to: encoder)
      var values = encoder.container(keyedBy: JSONValue.Key.self)
      for (key, value) in unknown { try values.encode(value, forKey: JSONValue.Key(key)) }
    }
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: JSONValue.Key.self)
    for key in values.allKeys where key != Self.artifactsKey {
      unknownTopLevel[key.stringValue] = try values.decode(JSONValue.self, forKey: key)
    }
    for record in try values.decode([Record].self, forKey: Self.artifactsKey) {
      guard let artifact = record.artifact, case .object(let fields) = record.json else {
        unreadable.append(record.json)
        continue
      }
      artifacts.append(artifact)
      asRead[artifact.id] = ReadRecord(artifact: artifact, fields: fields)
    }
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: JSONValue.Key.self)
    for (key, value) in unknownTopLevel { try values.encode(value, forKey: JSONValue.Key(key)) }
    var records = values.nestedUnkeyedContainer(forKey: Self.artifactsKey)
    for artifact in artifacts {
      if let read = asRead[artifact.id], read.artifact == artifact {
        try records.encode(JSONValue.object(read.fields))
      } else {
        let unknown = asRead[artifact.id]?.fields.filter { !Self.artifactFields.contains($0.key) }
        try records.encode(Stored(artifact: artifact, unknown: unknown ?? [:]))
      }
    }
    for record in unreadable { try records.encode(record) }
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

/// What `Inventory.mergeSweep` did.
public struct SweepMerge: Equatable, Sendable {
  public struct Ambiguity: Equatable, Sendable {
    /// The new record.
    public var added: UUID
    /// The saved records it could have been levelled from.
    public var earlier: [UUID]
  }

  /// Pieces the sweep read.
  public var read: Int
  /// Read pieces that were saved already.
  public var alreadySaved = 0
  /// New records.
  public var added: [UUID] = []
  /// Records a levelled-up piece replaced, keeping their IDs.
  public var replaced: [UUID] = []
  public var ambiguous: [Ambiguity] = []
  /// Saved records at levels the sweep covered that it didn't see: salvaged, fed, or levelled
  /// into a piece that couldn't be matched to them.
  public var unseen: [UUID] = []

  public init(read: Int) { self.read = read }
}
