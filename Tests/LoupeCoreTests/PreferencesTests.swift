import Foundation
import LoupeCore
import Testing

@Suite final class PreferencesTests {
  let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")

  deinit { try? FileManager.default.removeItem(at: file) }

  @Test func defaultsWhenNothingIsSaved() {
    let preferences = Preferences.read(from: file)
    #expect(preferences == Preferences())
    #expect(!preferences.collectCards)
    #expect(!preferences.bufferDiagnostics)
    #expect(preferences.profileName == "Crit")
    #expect(preferences.customWeights.values.allSatisfy { $0 == 0 })
  }

  @Test func roundTripsEverySetting() throws {
    var preferences = Preferences()
    preferences.collectCards = true
    preferences.bufferDiagnostics = true
    preferences.overlayExpanded = true
    preferences.manualProfile = true
    preferences.sameSet = true
    preferences.profileName = "Custom"
    preferences.customWeights[.critRate] = 100
    preferences.customWeights[.energyRecharge] = 40
    try preferences.write(to: file)
    #expect(Preferences.read(from: file) == preferences)
  }

  @Test func keepsWhatItCanReadFromABadFile() throws {
    let json = """
      {"collectCards": true, "overlayExpanded": "yes", "profileName": "Gone",
       "customWeights": {"critRate_": 250, "eleMas": -5, "pyro_dmg_": 50, "nonsense": 9}, "extra": 1}
      """
    try Data(json.utf8).write(to: file)
    let preferences = Preferences.read(from: file)
    #expect(preferences.collectCards)
    #expect(!preferences.overlayExpanded)
    #expect(preferences.profileName == "Crit")
    #expect(preferences.customWeights[.critRate] == 100)
    #expect(preferences.customWeights[.elementalMastery] == 0)
    #expect(preferences.customWeights[.pyroDamage] == nil)
    #expect(preferences.customWeights.count == Stat.substats.count)
  }

  @Test func readsGarbageAsDefaults() throws {
    try Data("not json".utf8).write(to: file)
    #expect(Preferences.read(from: file) == Preferences())
  }
}
