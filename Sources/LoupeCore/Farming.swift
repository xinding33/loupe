import Foundation

/// An artifact domain and the two five-star sets it drops, one or the other each time.
public struct ArtifactDomain: Sendable, Identifiable, Equatable {
  public let name: String
  public let sets: [String]
  public var id: String { name }

  init(_ name: String, _ first: String, _ second: String) {
    self.name = name
    self.sets = [first, second]
  }

  /// Every artifact domain through Version 7.0, by the region it opened in.
  public static let all: [ArtifactDomain] = [
    ArtifactDomain("Midsummer Courtyard", "Thundering Fury", "Thundersoother"),
    ArtifactDomain("Valley of Remembrance", "Viridescent Venerer", "Maiden Beloved"),
    ArtifactDomain("Domain of Guyun", "Archaic Petra", "Retracing Bolide"),
    ArtifactDomain("Hidden Palace of Zhou Formula", "Crimson Witch of Flames", "Lavawalker"),
    ArtifactDomain(
      "Clear Pool and Mountain Cavern", "Noblesse Oblige", "Bloodstained Chivalry"),
    ArtifactDomain("Peak of Vindagnyr", "Blizzard Strayer", "Heart of Depth"),
    ArtifactDomain("Ridge Watch", "Tenacity of the Millelith", "Pale Flame"),
    ArtifactDomain("Momiji-Dyed Court", "Emblem of Severed Fate", "Shimenawa's Reminiscence"),
    ArtifactDomain("Slumbering Court", "Husk of Opulent Dreams", "Ocean-Hued Clam"),
    ArtifactDomain("The Lost Valley", "Vermillion Hereafter", "Echoes of an Offering"),
    ArtifactDomain("Spire of Solitary Enlightenment", "Deepwood Memories", "Gilded Dreams"),
    ArtifactDomain("City of Gold", "Desert Pavilion Chronicle", "Flower of Paradise Lost"),
    ArtifactDomain("Molten Iron Fortress", "Nymph's Dream", "Vourukasha's Glow"),
    ArtifactDomain("Denouement of Sin", "Marechaussee Hunter", "Golden Troupe"),
    ArtifactDomain(
      "Waterfall Wen", "Song of Days Past", "Nighttime Whispers in the Echoing Woods"),
    ArtifactDomain("Faded Theater", "Fragment of Harmonic Whimsy", "Unfinished Reverie"),
    ArtifactDomain(
      "Derelict Masonry Dock", "Scroll of the Hero of Cinder City", "Obsidian Codex"),
    ArtifactDomain(
      "Sanctum of Rainbow Spirits", "Finale of the Deep Galleries", "Long Night's Oath"),
    ArtifactDomain(
      "Frostladen Machinery", "Night of the Sky's Unveiling", "Silken Moon's Serenade"),
    ArtifactDomain(
      "Moonchild's Treasures", "Aubade of Morningstar and Moon", "A Day Carved From Rising Winds"),
    ArtifactDomain(
      "Thorny Crown of the Mountain Wind", "Celestial Gift", "Disenchantment in Deep Shadow"),
    ArtifactDomain("Inverted Glacier", "Heart of the Furnace", "Scarlet Proof"),
  ]

  /// Five-star sets no domain drops. They come from bosses and the Artifact Strongbox.
  public static let bossSets = ["Gladiator's Finale", "Wanderer's Troupe"]

  public static func dropping(_ set: String) -> ArtifactDomain? {
    let key = Artifact.normalizeSet(set)
    return all.first { $0.sets.contains { Artifact.normalizeSet($0) == key } }
  }

  /// Whether a five-star piece of this set can be farmed at all, from a domain or a boss.
  static func isFiveStar(_ set: String) -> Bool {
    dropping(set) != nil
      || bossSets.contains { Artifact.normalizeSet($0) == Artifact.normalizeSet(set) }
  }
}

/// A character the player owns, the role Loupe builds it for, and whether it's being built now.
public struct OwnedCharacter: Codable, Equatable, Sendable, Identifiable {
  public let characterID: String
  public var roleID: String
  /// Counts double in the account's farming plan.
  public var building: Bool
  public var id: String { characterID }

  public init(characterID: String, roleID: String? = nil, building: Bool = false) {
    self.characterID = characterID
    self.roleID = roleID ?? Self.defaultRole(for: characterID)?.roleID ?? ""
    self.building = building
  }

  public var role: CharacterRole? { CharacterRoles.all.first { $0.roleID == roleID } }

  enum CodingKeys: String, CodingKey { case characterID, roleID, building }

  /// The role a character is built for unless the player picks another: the first of `roles`.
  public static func defaultRole(for characterID: String) -> CharacterRole? {
    roles(for: characterID).first
  }

  /// A character's roles in the roster's archetype order, so its first-listed archetype leads. A
  /// reviewed role takes the place of the archetype it matches; others follow it.
  public static func roles(for characterID: String) -> [CharacterRole] {
    let order = Roster.characters.first { $0.id == characterID }?.archetypes ?? []
    func rank(_ role: CharacterRole) -> Int {
      role.archetype.flatMap { order.firstIndex(of: $0) } ?? order.count
    }
    return CharacterRoles.all.enumerated().filter { $0.element.characterID == characterID }
      .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
  }

  /// Owned characters whose character and role are still in the dataset, once each. A role that
  /// isn't the character's falls back to the default.
  public static func valid(_ owned: [OwnedCharacter]) -> [OwnedCharacter] {
    var seen = Set<String>()
    return owned.compactMap { entry in
      guard defaultRole(for: entry.characterID) != nil, seen.insert(entry.characterID).inserted
      else { return nil }
      let fits = entry.role?.characterID == entry.characterID
      return OwnedCharacter(
        characterID: entry.characterID, roleID: fits ? entry.roleID : nil,
        building: entry.building)
    }
  }
}

/// One slot of one role's build: the piece it wears there now, and how often a drop beats it.
public struct FarmingNeed: Sendable, Identifiable {
  public let role: CharacterRole
  /// The role's four-piece set: the first five-star one it lists.
  public let set: String
  public let slot: Slot
  /// Mains the role uses in this slot.
  public let mains: [Stat]
  /// The piece to beat: the best saved +20 five-star piece of the set, slot and a main the role
  /// uses, or the off-set piece the build wears here instead.
  public let best: Artifact?
  /// That piece's grade for the role, or nil when it has none, such as an EM sands for an EM role.
  public let bestGrade: ArtifactTier?
  /// The build's one off-set slot, where `best` is of another set.
  public let offSet: Bool
  /// Chance one five-star drop from the set's domain is an upgrade here. See `FarmingPlan`.
  public let chancePerDrop: Double
  /// How much the account plan counts this role: 2 for a character being built now, else 1.
  public internal(set) var weight = 1.0
  public var id: String { "\(role.roleID)|\(slot.rawValue)" }

  /// Expected five-star domain drops before one is an upgrade here.
  public var dropsPerUpgrade: Double? { chancePerDrop > 0 ? 1 / chancePerDrop : nil }
  /// Nothing from a domain can beat what's worn: a main-only fit is saved.
  public var isFilled: Bool { best != nil && chancePerDrop == 0 }
  /// Worn with a piece at A or better, or filled by a main-only fit.
  public var isReady: Bool {
    best != nil && (bestGrade.map { $0 == .s || $0 == .a } ?? true)
  }
}

/// What one character's build wears and what its set's domain can still improve.
public struct CharacterFarming: Sendable, Identifiable {
  public let role: CharacterRole
  /// The four-piece set it farms, or nil when it lists no five-star set.
  public let set: String?
  /// Every slot, in slot order; empty without a set.
  public let slots: [FarmingNeed]
  public var id: String { role.roleID }
  public var domain: ArtifactDomain? { self.set.flatMap(ArtifactDomain.dropping) }
  /// Expected upgrades per five-star drop from the set's domain, over every slot.
  public var upgradesPerDrop: Double { slots.reduce(0) { $0 + $1.chancePerDrop } }
  public var dropsPerUpgrade: Double? { upgradesPerDrop > 0 ? 1 / upgradesPerDrop : nil }
  public var offSetSlot: Slot? { slots.first(where: \.offSet)?.slot }
  /// Whether a domain drops the set, so runs and Resin per upgrade mean something. Boss-only
  /// sets' chances assume a domain's two-set split and aren't shown as runs.
  public var hasDomain: Bool { domain != nil }
}

/// A domain worth farming, with the upgrades it can drop for the chosen roles.
public struct DomainSuggestion: Sendable, Identifiable {
  public let domain: ArtifactDomain
  /// Most weighted upgrades first.
  public let needs: [FarmingNeed]
  public var id: String { domain.id }

  /// Expected upgrades per five-star drop, summed over every need, so a drop two roles could
  /// use counts twice.
  public var upgradesPerDrop: Double { needs.reduce(0) { $0 + $1.chancePerDrop } }
  public var dropsPerUpgrade: Double? { upgradesPerDrop > 0 ? 1 / upgradesPerDrop : nil }
  /// The same sum with characters being built counted double, for the order.
  public var priority: Double { needs.reduce(0) { $0 + $1.chancePerDrop * $1.weight } }
}

/// How well an account's saved pieces cover the builds that wear one set.
public struct SetStrength: Sendable, Identifiable {
  public let set: String
  /// The builds that farm it.
  public let builds: [CharacterFarming]
  public var id: String { self.set }
  public var domain: ArtifactDomain? { ArtifactDomain.dropping(self.set) }
  public var slots: [FarmingNeed] { builds.flatMap(\.slots) }
  public var readySlots: Int { slots.filter(\.isReady).count }
  public var totalSlots: Int { slots.count }
  public var readiness: Double { totalSlots == 0 ? 1 : Double(readySlots) / Double(totalSlots) }
  public var upgradesPerDrop: Double { builds.reduce(0) { $0 + $1.upgradesPerDrop } }
  public var hasDomain: Bool { domain != nil }
  public var level: Level { readiness >= 0.8 ? .strong : readiness >= 0.4 ? .fair : .weak }

  public enum Level: String, Sendable {
    case strong = "Strong"
    case fair = "Fair"
    case weak = "Weak"
  }
}

/// What to farm, for one character or a whole account.
///
/// Each role wears its four-piece set: the first five-star set it lists. A new drop is an
/// upgrade for a role when it's that set, in a slot and with a main stat the role uses, and its
/// final +20 score for the role is above the piece worn there and at least the role's A cutoff
/// (`RollGrade`), so an empty slot isn't filled by a piece the verdicts would feed. Mains the
/// role uses count as equal, compared by substats. A main the role values only as its main stat,
/// such as an EM sands for an EM role, beats any piece of another main whatever its substats,
/// and one worn fills the slot.
///
/// The piece worn is the best saved +20 piece of the set, slot and a used main, except in the
/// one off-set slot a 4+1 build allows. That slot takes the best saved piece of another set
/// where it beats the set's own under the upgrade rule, and, among those slots, where it's
/// rarer among drops than the set's own by the widest margin. Drops of the set have to beat
/// that off-set piece there.
///
/// The chance per drop is exact for top-level domain drops: half for the set, a fifth for the
/// slot, the main-stat odds, and the share of drops of that main finishing high enough
/// (`DropRarity`). A domain's value is the expected upgrades per drop, summed over the roles'
/// slots from its two sets, so one piece two roles could use counts for both. Off-set drops
/// aren't counted: any domain drops them alike, so they don't change the order.
public enum FarmingPlan {
  public struct Result: Sendable {
    /// Domains with at least one need, most weighted upgrades per drop first.
    public let domains: [DomainSuggestion]
    /// Sets the roles farm, weakest first.
    public let sets: [SetStrength]
    /// Needs for sets only bosses and strongboxes drop, likeliest first. Their chance assumes
    /// the set is one of two, as in a domain.
    public let bossNeeds: [FarmingNeed]
    /// Roles with no five-star set Loupe knows how to farm.
    public let unfarmable: [CharacterRole]
  }

  /// The set a role farms: the first five-star set it lists. Four-star-only sets such as
  /// Instructor are skipped.
  public static func set(for role: CharacterRole) -> String? {
    role.sets.map(\.name).first(where: ArtifactDomain.isFiveStar)
  }

  /// Every account role with its weight: owned characters, the ones being built counted double,
  /// or every character's default role when none are entered.
  public static func roles(owned: [OwnedCharacter]) -> [(role: CharacterRole, weight: Double)] {
    guard !owned.isEmpty else {
      var seen = Set<String>()
      return CharacterRoles.all.map(\.characterID).filter { seen.insert($0).inserted }
        .compactMap { OwnedCharacter.defaultRole(for: $0).map { ($0, 1) } }
    }
    return owned.compactMap { entry in entry.role.map { ($0, entry.building ? 2 : 1) } }
  }

  public static func evaluate(
    roles: [(role: CharacterRole, weight: Double)], inventory: [Artifact]
  ) -> Result {
    var byDomain: [String: [FarmingNeed]] = [:]
    var bySet: [String: [CharacterFarming]] = [:]
    var boss: [FarmingNeed] = []
    var unfarmable: [CharacterRole] = []
    // A cancelled refresh stops early; its partial result is thrown away.
    for (role, weight) in roles where !Task.isCancelled {
      let build = character(role, inventory: inventory)
      guard let set = build.set else {
        unfarmable.append(role)
        continue
      }
      bySet[set, default: []].append(build)
      let needs = build.slots.filter { $0.chancePerDrop > 0 }.map {
        var need = $0
        need.weight = weight
        return need
      }
      if let domain = build.domain {
        byDomain[domain.name, default: []] += needs
      } else {
        boss += needs
      }
    }
    func first(_ a: FarmingNeed, _ b: FarmingNeed) -> Bool {
      let (x, y) = (a.chancePerDrop * a.weight, b.chancePerDrop * b.weight)
      return x == y ? a.id < b.id : x > y
    }
    var domains: [DomainSuggestion] = []
    for domain in ArtifactDomain.all {
      guard let needs = byDomain[domain.name], !needs.isEmpty else { continue }
      domains.append(DomainSuggestion(domain: domain, needs: needs.sorted(by: first)))
    }
    domains.sort { (a: DomainSuggestion, b: DomainSuggestion) -> Bool in
      a.priority == b.priority ? a.domain.name < b.domain.name : a.priority > b.priority
    }
    var sets = bySet.map { SetStrength(set: $0.key, builds: $0.value) }
    sets.sort { (a: SetStrength, b: SetStrength) -> Bool in
      if a.readiness != b.readiness { return a.readiness < b.readiness }
      if a.builds.count != b.builds.count { return a.builds.count > b.builds.count }
      return a.set < b.set
    }
    return Result(
      domains: domains, sets: sets, bossNeeds: boss.sorted(by: first), unfarmable: unfarmable)
  }

  /// One role's build, slot by slot.
  public static func character(_ role: CharacterRole, inventory: [Artifact]) -> CharacterFarming {
    guard let set = set(for: role) else { return CharacterFarming(role: role, set: nil, slots: []) }
    let key = Artifact.normalizeSet(set)
    let finished = inventory.filter { $0.level == 20 && $0.rarity == 5 }
    func pool(_ slot: Slot, onSet: Bool) -> [Artifact] {
      let mains = role.mains[slot, default: []]
      return finished.filter {
        $0.slot == slot && mains.contains($0.main) && ($0.setKey == key) == onSet
      }
    }
    // The off-set slot takes another set's best piece where it beats the set's own the way an
    // upgrade would, and where it's rarest among drops compared with the set's own.
    var offSet: (slot: Slot, piece: Artifact, gain: Double)?
    for slot in Slot.allCases {
      guard let other = best(pool(slot, onSet: false), role: role) else { continue }
      let own = best(pool(slot, onSet: true), role: role)
      guard own.map({ beats(other, $0, role: role) }) ?? true else { continue }
      let gain = (own.map { share($0, role: role) } ?? 1) - share(other, role: role)
      if offSet.map({ gain > $0.gain }) ?? true { offSet = (slot, other, gain) }
    }
    let slots = Slot.allCases.compactMap { slot in
      offSet?.slot == slot
        ? need(role, set: set, slot: slot, worn: offSet.map { [$0.piece] } ?? [], offSet: true)
        : need(role, set: set, slot: slot, worn: pool(slot, onSet: true), offSet: false)
    }
    return CharacterFarming(role: role, set: set, slots: slots)
  }

  /// Graded when a useful stat other than the main can roll on it, as in `TierCalibration`.
  static func graded(_ main: Stat, role: CharacterRole) -> Bool {
    role.usefulStats.contains { $0 != main }
  }

  /// The piece a role wears from these: a main-only fit, or the highest substat score.
  static func best(_ pieces: [Artifact], role: CharacterRole) -> Artifact? {
    let profile = role.profile
    return pieces.first { !graded($0.main, role: role) }
      ?? pieces.max { profile.score($0.substats) < profile.score($1.substats) }
  }

  /// Whether a piece would replace another under the upgrade rule: a main-only fit beats any
  /// piece of a graded main, and pieces of graded mains compare by substat score.
  static func beats(_ piece: Artifact, _ other: Artifact, role: CharacterRole) -> Bool {
    switch (graded(piece.main, role: role), graded(other.main, role: role)) {
    case (false, _): graded(other.main, role: role)
    case (true, false): false
    case (true, true): role.profile.score(piece.substats) > role.profile.score(other.substats)
    }
  }

  /// Share of new drops of the piece's slot and main finishing at or above it for the role, so
  /// smaller is rarer. A main-only fit can't be beaten.
  static func share(_ piece: Artifact, role: CharacterRole) -> Double {
    guard graded(piece.main, role: role) else { return 0 }
    return RarityCache.shared.rarity(piece.slot, piece.main, role.profile)?
      .shareAtOrAbove(role.profile.score(piece.substats)) ?? 1
  }

  static func need(
    _ role: CharacterRole, set: String, slot: Slot, worn: [Artifact], offSet: Bool
  ) -> FarmingNeed? {
    let mains = role.mains[slot, default: []]
    guard !mains.isEmpty else { return nil }
    let profile = role.profile
    func score(_ piece: Artifact) -> Int { profile.score(piece.substats) }
    let best = best(worn, role: role)
    let filled = best.map { !graded($0.main, role: role) } ?? false
    let bestGrade = best.flatMap { piece in
      graded(piece.main, role: role)
        ? RarityCache.shared.rarity(slot, piece.main, profile).map {
          RollGrade.tier(Double(score(piece)), cutoffs: RollGrade.cutoffs($0, profile: profile))
        } : nil
    }
    var share = 0.0
    if !filled {
      for main in mains {
        let odds = slot.mainStatOdds[main] ?? 0
        // Nothing worn is a main-only fit, or the slot would be filled, so one always helps.
        guard graded(main, role: role) else {
          share += odds
          continue
        }
        guard let rarity = RarityCache.shared.rarity(slot, main, profile),
          let a = RollGrade.cutoffs(rarity, profile: profile).first(where: { $0.tier == .a })
        else { continue }
        // Finished scores are whole units: at least the A cutoff, and above the piece worn.
        let floor = Int((a.minimum - 1e-6).rounded(.up))
        let threshold = max(floor, best.map { score($0) + 1 } ?? floor)
        share += odds * rarity.shareAtOrAbove(threshold)
      }
    }
    return FarmingNeed(
      role: role, set: set, slot: slot, mains: mains, best: best, bestGrade: bestGrade,
      offSet: offSet, chancePerDrop: 0.5 / Double(Slot.allCases.count) * share)
  }
}
