import Foundation
import LoupeCore
import Testing

@Suite final class PreferencesTests {
  let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).json")

  deinit { try? FileManager.default.removeItem(at: file) }

  @Test func defaultsWhenNothingIsSaved() {
    let preferences = Preferences.read(from: file)
    #expect(preferences == Preferences())
    #expect(preferences.collectCards)
    #expect(!preferences.bufferDiagnostics)
    #expect(preferences.profileName == "Crit")
    #expect(preferences.customWeights.values.allSatisfy { $0 == 0 })
  }

  @Test func roundTripsEverySetting() throws {
    var preferences = Preferences()
    preferences.collectCards = false
    preferences.bufferDiagnostics = true
    preferences.overlayExpanded = true
    preferences.manualProfile = true
    preferences.sameSet = true
    preferences.profileName = "Custom"
    preferences.customWeights[.critRate] = 100
    preferences.customWeights[.energyRecharge] = 40
    preferences.ownedCharacters = [
      OwnedCharacter(characterID: "kazuha", building: true),
      OwnedCharacter(characterID: "raiden-shogun", roleID: "raiden-shogun.er-crit"),
    ]
    try preferences.write(to: file)
    #expect(Preferences.read(from: file) == preferences)
  }

  @Test func keepsWhatItCanReadFromABadFile() throws {
    let json = """
      {"collectWhileBrowsing": false, "overlayExpanded": "yes", "profileName": "Gone",
       "customWeights": {"critRate_": 250, "eleMas": -5, "pyro_dmg_": 50, "nonsense": 9}, "extra": 1}
      """
    try Data(json.utf8).write(to: file)
    let preferences = Preferences.read(from: file)
    #expect(!preferences.collectCards)
    #expect(!preferences.overlayExpanded)
    #expect(preferences.profileName == "Crit")
    #expect(preferences.customWeights[.critRate] == 100)
    #expect(preferences.customWeights[.elementalMastery] == 0)
    #expect(preferences.customWeights[.pyroDamage] == nil)
    #expect(preferences.customWeights.count == Stat.substats.count)
  }

  @Test func skipsOwnedCharactersItCannotUse() throws {
    let json = #"""
      {"ownedCharacters": [
        {"characterID": "furina", "roleID": "gone.role", "building": true},
        {"characterID": "nobody"},
        null,
        3,
        {"roleID": "kazuha.em-swirl-support"},
        {"characterID": "furina"},
        {"characterID": "kazuha", "building": "yes"}
      ]}
      """#
    try Data(json.utf8).write(to: file)
    let owned = Preferences.read(from: file).ownedCharacters
    #expect(
      owned == [
        OwnedCharacter(characterID: "furina", roleID: "furina.off-field-hp", building: true),
        OwnedCharacter(characterID: "kazuha", roleID: "kazuha.em-swirl-support"),
      ])
  }

  @Test func collectingStartsOnWhateverAnOlderFileSaid() throws {
    try Data(#"{"collectCards": false, "overlayExpanded": true}"#.utf8).write(to: file)
    let preferences = Preferences.read(from: file)
    #expect(preferences.collectCards)
    #expect(preferences.overlayExpanded)
  }

  @Test func readsGarbageAsDefaults() throws {
    try Data("not json".utf8).write(to: file)
    #expect(Preferences.read(from: file) == Preferences())
  }
}
