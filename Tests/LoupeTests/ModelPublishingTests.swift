import Combine
import Foundation
import LoupeCore
import Testing

@testable import Loupe

private let publishingCard = """
  Holy Crown of the Believer
  Circlet of Logos
  CRIT DMG
  9.3%
  +0
  ATK+18
  HP+4.1%
  Energy Recharge+5.2%
  DEF+5.1% (unactivated)
  Silken Moon's Serenade:
  """

private let publishingFlower = """
  Dreaming Steelbloom
  Flower of Life
  HP
  4,780
  +20
  Elemental Mastery+117
  HP+5.8%
  CRIT Rate+7.8%
  DEF+23
  Gilded Dreams:
  """

@MainActor
private final class Emissions {
  private(set) var count = 0
  private var subscription: AnyCancellable?
  init(_ model: Model) {
    subscription = model.objectWillChange.sink { [weak self] _ in self?.count += 1 }
  }
}

@MainActor
@Test func modelStaysQuietWhileTheSameCardIsRead() throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  let reading = CardReading(text: publishingCard, stars: 5, confidence: 1)
  model.capture.receive?(.success(reading))
  model.capture.receive?(.success(reading))
  #expect(model.stability.isVerified)
  #expect(model.current != nil)

  // Synchronous from here, so neither the live freshness timer nor the evaluation finishing can
  // land in between.
  let emissions = Emissions(model)
  for _ in 0..<3 { model.capture.receive?(.success(reading)) }
  // A freshness tick before the card expires.
  model.checkFreshness(at: Date().addingTimeInterval(1))
  #expect(model.stability.isVerified)
  #expect(emissions.count == 0)

  // The tick that expires it still shows.
  model.checkFreshness(at: Date().addingTimeInterval(3))
  #expect(!model.stability.isVerified)
  #expect(model.current == nil)
  #expect(model.status.hasPrefix("No fresh card"))
  #expect(emissions.count > 0)
}

@MainActor
@Test func modelStaysQuietWhileNoCardIsShowing() throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  let missing = ArtifactError("Open one artifact card in Inventory.")
  model.capture.receive?(.failure(missing))
  #expect(model.status == missing.localizedDescription)
  let emissions = Emissions(model)
  for _ in 0..<3 { model.capture.receive?(.failure(missing)) }
  #expect(emissions.count == 0)
}

@MainActor
@Test func modelPlacementStatusPublishesOnlyChanges() throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  let emissions = Emissions(model)
  model.setPlacementStatus(model.placementStatus)
  #expect(emissions.count == 0)
  model.setPlacementStatus("Anchored.")
  model.setPlacementStatus("Anchored.")
  #expect(emissions.count == 1)
  #expect(model.placementStatus == "Anchored.")
}

@MainActor
@Test func modelBuildsTheShortlistOncePerChange() async throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  model.useText(publishingFlower, confirmed: true)
  await model.evaluate()?.value
  let matches = model.characterMatches
  let verdict = try #require(model.verdict)
  #expect(matches.count > 1)

  /// Counts the builds for a change and everything a render then reads, several times over.
  func builds(after change: () -> Void) -> Int {
    let before = model.shortlistBuilds
    change()
    for _ in 0..<5 {
      _ = model.characterShortlist
      _ = model.selectedMatch
      _ = model.displayedPotential
      _ = model.displayedScope
      _ = model.recommendation
    }
    return model.shortlistBuilds - before
  }
  #expect(builds {} <= 1)
  #expect(builds {} == 0)
  let other = try #require(matches.last { $0.characterID != model.selectedMatch?.characterID })
  #expect(builds { model.selectedCharacterID = other.characterID } == 1)
  #expect(model.selectedMatch?.characterID == other.characterID)
  #expect(builds { model.selectedRoleID = other.roleID } == 1)
  #expect(builds { model.verdict = nil } == 1)
  #expect(builds { model.verdict = verdict } == 1)
  #expect(builds { model.characterMatches = [] } == 1)
  #expect(model.selectedMatch == nil)
  #expect(builds { model.characterMatches = matches } == 1)
  #expect(model.selectedMatch?.roleID == other.roleID)
  #expect(builds { model.current = nil } == 1)
  #expect(model.characterShortlist.allMatches.isEmpty)
}

@MainActor
@Test func modelFillsTheProfileOverviewOnlyInProfileMode() async throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  defer { model.setEnabled(false) }
  model.assessmentMode = .characters
  model.useText(publishingCard, confirmed: true)
  await model.evaluate()?.value
  let artifact = try #require(model.current)
  let matches = model.characterMatches.map(\.roleID)
  let verdict = model.verdict
  #expect(!matches.isEmpty)
  #expect(model.potential != nil)
  #expect(model.allProfiles.isEmpty)

  let expected = Profile.presets.compactMap { preset in
    (try? Potential.evaluate(artifact, profile: preset, inventory: [], scope: .offPiece))
      .map { (preset.id, $0.expectedScore) }
  }
  #expect(expected.count == Profile.presets.count)
  model.assessmentMode = .profile
  // The character results stay on screen while the overview fills in.
  #expect(model.characterMatches.map(\.roleID) == matches)
  #expect(model.verdict == verdict)
  await model.overviewFill?.value
  #expect(model.allProfiles.map(\.name) == expected.map(\.0))
  #expect(model.allProfiles.map(\.result.expectedScore) == expected.map(\.1))
  #expect(model.characterMatches.map(\.roleID) == matches)
  #expect(model.verdict == verdict)

  // In profile mode a new profile or scope evaluates everything again, overview included.
  model.profileName = "HP + crit"
  await model.evaluate()?.value
  #expect(model.allProfiles.count == expected.count)
  #expect(model.characterMatches.map(\.roleID) == matches)

  model.assessmentMode = .characters
  await model.evaluate()?.value
  #expect(model.allProfiles.isEmpty)
  #expect(model.characterMatches.map(\.roleID) == matches)
}
