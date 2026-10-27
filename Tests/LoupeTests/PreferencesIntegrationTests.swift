import Foundation
import LoupeCore
import Testing

@testable import Loupe

@MainActor
@Test func settingsOutlastARelaunch() throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let inventory = folder.appending(path: "inventory.json")
  let first = Model(inventoryFile: inventory)
  first.setCollectCards(true)
  first.diagnostics.setOptedIn(true)
  first.overlayExpanded = true
  first.assessmentMode = .profile
  first.scope = .sameSet
  first.profileName = "Custom"
  first.customWeights[.energyRecharge] = 40
  first.special = true
  // Quitting turns the reader off, which must not forget the collection choice.
  first.setEnabled(false)

  let second = Model(inventoryFile: inventory)
  #expect(second.scanMode)
  #expect(second.diagnostics.optedIn)
  #expect(second.overlayExpanded)
  #expect(second.assessmentMode == .profile)
  #expect(second.scope == .sameSet)
  #expect(second.profileName == "Custom")
  #expect(second.customWeights[.energyRecharge] == 40)
  #expect(!second.special)
}

@MainActor
@Test func turningTheReaderBackOnRestoresTheCollectionChoice() {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: folder) }
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  model.setCollectCards(true)
  model.setEnabled(false)
  #expect(!model.scanMode)
  model.setEnabled(true)
  #expect(model.scanMode)
  model.setCollectCards(false)
  model.setEnabled(false)
  model.setEnabled(true)
  #expect(!model.scanMode)
}
