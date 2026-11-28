import AppKit
import LoupeCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class Model: ObservableObject {
  @Published var inventory = Inventory()
  @Published var current: Artifact? {
    didSet { cachedShortlist = nil }
  }
  @Published var potential: Potential?
  @Published var characterMatches: [CharacterMatch] = [] {
    didSet { cachedShortlist = nil }
  }
  /// Keep / Level / Review / Fodder advice across every character match and the saved inventory.
  @Published var verdict: Verdict? {
    didSet { cachedShortlist = nil }
  }
  @Published var assessmentMode: AssessmentMode = .characters {
    didSet {
      preferences.manualProfile = assessmentMode == .profile
      if assessmentMode == .profile && allProfiles.isEmpty { fillProfileOverview() }
      refreshDiagnosticRecommendation()
    }
  }
  @Published var selectedCharacterID: String? {
    didSet {
      cachedShortlist = nil
      refreshDiagnosticRecommendation()
    }
  }
  /// The chosen role of the selected character, when it holds several.
  @Published var selectedRoleID: String? {
    didSet {
      cachedShortlist = nil
      refreshDiagnosticRecommendation()
    }
  }
  @Published private(set) var evaluationIssue: String?
  @Published var profileName = "Crit" {
    didSet {
      preferences.profileName = profileName
      evaluate()
    }
  }
  @Published var scope: ComparisonScope = .offPiece {
    didSet {
      preferences.sameSet = scope == .sameSet
      evaluate()
    }
  }
  @Published var customWeights = Dictionary(uniqueKeysWithValues: Stat.substats.map { ($0, 0) }) {
    didSet {
      preferences.customWeights = customWeights
      evaluate()
    }
  }
  @Published var status = "Choose the game window to start. Screens stay on this Mac."
  @Published var issue: String?
  @Published var rawText = ""
  @Published var recordingStatus =
    "Snapshots and recordings of the game window stay on this Mac and may include UID and chat."
  @Published var isRecording = false
  /// The last snapshot or recording, for Show in Finder.
  @Published private(set) var lastCapture: URL?
  /// Collection for this session. Linking, a failed save and turning the reader off stop it
  /// without changing the remembered choice; see `setCollectCards`.
  @Published var scanMode = false
  @Published var special = false {
    didSet {
      resetLiveCard()
      enhancementContext = nil
    }
  }
  @Published var linkedID: UUID?
  /// An inventory scan is clicking through the game. Collection pauses and the overlay hides.
  @Published private(set) var isScanning = false
  /// A scan turned collection off for the rest of this launch.
  private var collectionPausedByScan = false
  /// What the last inventory scan added, for the review list under Saved inventory.
  @Published var lastScan: ScanReport?
  /// Each Inventory card parsed while scanning, nil for a frame with none, before it's verified,
  /// with when its frame arrived.
  var cardObserver: ((InventorySweep.Card?, TimeInterval) -> Void)?
  @Published var search = ""
  @Published private(set) var enabled = true
  @Published var overlayExpanded = false {
    didSet {
      preferences.overlayExpanded = overlayExpanded
      updateOverlay?()
    }
  }
  @Published private(set) var placementStatus = "Choose a game window to place the overlay."
  @Published var shortcutStatus = ""
  @Published var expandShortcut =
    UserDefaults.standard.string(forKey: "expandShortcut") ?? "option+`"
  @Published var enableShortcut =
    UserDefaults.standard.string(forKey: "enableShortcut") ?? "option+shift+`"
  @Published var snapshotShortcut =
    UserDefaults.standard.string(forKey: "snapshotShortcut") ?? "option+shift+s"
  @Published var recordShortcut =
    UserDefaults.standard.string(forKey: "recordShortcut") ?? "option+shift+r"
  /// The presets compared side by side, computed only for manual-profile mode, which shows them.
  @Published var allProfiles: [(name: String, result: Potential)] = []
  let capture: Capture
  let diagnostics: DiagnosticReportFlow
  /// Not `@Published`: its timestamps change on every frame, so `updateStability` announces only
  /// a change in what views read.
  private(set) var stability = CardStability()
  private let file: URL
  private let preferencesFile: URL
  private var preferences: Preferences {
    didSet {
      guard preferences != oldValue else { return }
      do { try preferences.write(to: preferencesFile) } catch {
        issue = "Cannot save settings. \(error.localizedDescription)"
      }
    }
  }
  private var freshness: Timer?
  private var evaluation: Task<Void, Never>?
  /// Fills the preset overview after a switch to manual-profile mode.
  private(set) var overviewFill: Task<Void, Never>?
  /// Views read the shortlist many times per render, so it's built once per change of its inputs.
  private var cachedShortlist: CharacterShortlist?
  /// How many times the shortlist has been built, for tests.
  private(set) var shortlistBuilds = 0
  private var undoInventory: Inventory?
  private var persistenceAvailable = true
  private var enhancementContext: (pieceName: String, artifact: Artifact)?
  private var latestDiagnosticSample: DiagnosticSampleKey?
  private var displayedDiagnosticSample: UUID?
  private var diagnosticRecommendation: DiagnosticRecommendation?
  var diagnosticPlacement: DiagnosticPlacement?
  var updateOverlay: (() -> Void)?
  var resetOverlayPlacement: (() -> Void)?
  var applyShortcuts: (() -> Void)?
  /// A brief confirmation that shows over a full-screen game.
  var banner: ((String) -> Void)?
  // Clear diagnostic evidence whenever the reader changes enabled state.
  var clearDiagnostics: (() -> Void)?
  private var readingGeneration = UUID()

  init(inventoryFile: URL? = nil) {
    let source = Capture()
    capture = source
    diagnostics = DiagnosticReportFlow { source.setDiagnosticsEnabled($0) }
    let folder =
      inventoryFile?.deletingLastPathComponent()
      ?? URL.applicationSupportDirectory.appending(
        path: "Loupe", directoryHint: .isDirectory)
    file = inventoryFile ?? folder.appending(path: "inventory.json")
    preferencesFile = folder.appending(path: "preferences.json")
    let saved = Preferences.read(from: preferencesFile)
    preferences = saved
    scanMode = saved.collectCards
    overlayExpanded = saved.overlayExpanded
    assessmentMode = saved.manualProfile ? .profile : .characters
    scope = saved.sameSet ? .sameSet : .offPiece
    profileName = saved.profileName
    customWeights = saved.customWeights
    diagnostics.setOptedIn(saved.bufferDiagnostics)
    diagnostics.didChangeOptIn = { [weak self] in self?.preferences.bufferDiagnostics = $0 }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      if FileManager.default.fileExists(atPath: file.path) {
        inventory = try Inventory.read(from: file)
      }
    } catch {
      persistenceAvailable = false
      issue =
        "Cannot load inventory; saving is disabled to protect the existing file. \(error.localizedDescription)"
    }
    capture.status = { [weak self] in self?.status = $0 }
    capture.recordingStatus = { [weak self] message, active in
      guard let self else { return }
      if isRecording && !active { banner?("Recording stopped") }
      if !isRecording && active { banner?("Recording") }
      recordingStatus = message
      isRecording = active
    }
    capture.recordingSaved = { [weak self] in self?.lastCapture = $0 }
    capture.didStop = { [weak self] in
      self?.enhancementContext = nil
      self?.resetLiveCard()
      self?.diagnostics.beginSession(nil)
    }
    capture.diagnosticSessionStarted = { [weak self] in self?.diagnostics.beginSession($0) }
    capture.diagnosticCoverage = { [weak self] session, coverage in
      self?.diagnostics.updateCoverage(coverage, session: session)
    }
    capture.receive = { [weak self] in self?.receive($0) }
    capture.setEnabled(true)
    startFreshnessTimer()
  }

  private func startFreshnessTimer() {
    freshness = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.checkFreshness(at: Date()) }
    }
  }

  /// The freshness timer's tick: clears a card no frame has verified for a while.
  func checkFreshness(at date: Date) {
    guard enabled else { return }
    capture.expireDiagnostics()
    guard updateStability({ $0.expire(at: date) }) else { return }
    clearResult()
    status = "No fresh card. Waiting for a readable artifact."
    recordDiagnosticDisplay()
  }

  var profile: Profile {
    profileName == "Custom"
      ? Profile("Custom", weights: customWeights)
      : Profile.presets.first { $0.id == profileName } ?? Profile.presets[0]
  }
  var visibleInventory: [Artifact] {
    inventory.artifacts.filter {
      search.isEmpty
        || "\($0.setName) \($0.slot.label) \($0.main.label) +\($0.level)"
          .localizedCaseInsensitiveContains(search)
    }.reversed()
  }
  var upgradedCount: Int { inventory.artifacts.filter { $0.level == 20 }.count }
  var canSaveCurrent: Bool { enabled && current != nil && stability.isVerified }
  var characterShortlist: CharacterShortlist {
    if let cachedShortlist { return cachedShortlist }
    let shortlist = CharacterShortlist(
      matches: characterMatches, artifact: current, selectedCharacterID: selectedCharacterID,
      selectedRoleID: selectedRoleID, leadingCharacterID: verdict?.characterID,
      leadingRoleID: verdict?.roleID, standings: verdict?.standings ?? [:])
    cachedShortlist = shortlist
    shortlistBuilds += 1
    return shortlist
  }
  var selectedMatch: CharacterMatch? { characterShortlist.selectedMatch }
  /// A character role compares with the saved pieces it would wear; a profile follows the picker.
  var displayedScope: ComparisonScope {
    assessmentMode == .characters ? selectedMatch?.scope ?? scope : scope
  }
  var displayedPotential: Potential? {
    assessmentMode == .characters ? selectedMatch?.potential : potential
  }
  var recommendation: String {
    if current?.rarity == 4 { return "Four-star: judged by set and main stat" }
    guard let current, let potential = displayedPotential else {
      return "Waiting for an assessment"
    }
    if current.isFinished { return "Fully upgraded" }
    if potential.maximumScore <= potential.currentScore { return "No further gain in this profile" }
    if potential.chanceToBeatBest == 0 {
      return "Ceiling cannot beat the best saved piece"
    }
    return UpgradeGuidance.checkpoint(current)
  }

  private func receive(_ result: Result<CardReading, Error>) {
    guard enabled else { return }
    let key = capture.currentSample
    let frameTime = capture.currentFrameTime ?? ProcessInfo.processInfo.systemUptime
    latestDiagnosticSample = key
    var parsed: Artifact?
    var decision = "OCR did not produce a confirmed reading"
    defer {
      if let key {
        capture.finishDiagnosticReading(
          key, artifact: parsed, decision: decision, state: diagnosticState())
      }
    }
    switch result {
    case .failure(let error):
      decision = error.localizedDescription
      cardObserver?(nil, frameTime)
      missedReading(error)
    case .success(let reading):
      if rawText != reading.text { rawText = reading.text }
      do {
        let artifact: Artifact
        if reading.isEnhancement {
          guard let context = enhancementContext else {
            throw ArtifactError("Read this piece in Inventory first, then open Enhance.")
          }
          artifact = try reading.resolveEnhancement(
            previous: context.artifact, pieceName: context.pieceName)
        } else {
          guard reading.confidence >= 0.65 else {
            throw ArtifactError("Low-confidence text. Waiting for a sharper Inventory card.")
          }
          artifact = try CardParser.parse(
            reading.text, stars: reading.stars,
            rule: special ? .special : .ordinary)
        }
        parsed = artifact
        cardObserver?(reading.isEnhancement ? nil : .read(artifact), frameTime)
        decision = "Parsed; checking card stability"
        updateStability { $0.observe(artifact.signature, at: Date()) }
        guard stability.isVerified else {
          if stability.signature == nil { clearResult() }
          showStatus(
            current == nil
              ? "Checking the next frame..."
              : "Rechecking the last verified card. Saving is paused."
          )
          return
        }
        if reading.isEnhancement {
          enhancementContext?.artifact = artifact
          showStatus(
            "Enhance verified against the last Inventory card. Odds update after rolls settle.")
        } else {
          enhancementContext = (CardParser.pieceName(reading.text), artifact)
          showStatus("Live card verified across two frames. Ordinary-drop model only.")
        }
        decision = "Parsed and verified across frames"
        if current?.signature == artifact.signature, let key {
          displayedDiagnosticSample = key.id
          if diagnosticRecommendation == nil { refreshDiagnosticRecommendation() }
        }
        if current?.signature != artifact.signature {
          current = artifact
          displayedDiagnosticSample = key?.id
          evaluate()
        }
        if scanMode && !isScanning && (!reading.isEnhancement || linkedID != nil) {
          saveCurrent()
        }
      } catch {
        decision = error.localizedDescription
        if parsed == nil { cardObserver?(Self.otherCard(result), frameTime) }
        missedReading(error)
      }
    }
  }

  /// An Inventory card of a rarity Loupe doesn't grade, one to three stars, for the scan to
  /// pass over.
  private static func otherCard(_ result: Result<CardReading, Error>) -> InventorySweep.Card? {
    guard case .success(let reading) = result, !reading.isEnhancement,
      (1...3).contains(reading.stars), reading.confidence >= 0.65,
      let card = CardParser.glance(reading.text)
    else { return nil }
    return .other(key: card.key, level: card.level)
  }

  private func clearResult() {
    evaluation?.cancel()
    evaluation = nil
    overviewFill?.cancel()
    overviewFill = nil
    displayedDiagnosticSample = nil
    diagnosticRecommendation = nil
    // Card-less frames clear several times a second, so only what's still showing is cleared.
    if current != nil { current = nil }
    if potential != nil { potential = nil }
    if !allProfiles.isEmpty { allProfiles = [] }
    if !characterMatches.isEmpty { characterMatches = [] }
    if verdict != nil { verdict = nil }
    if evaluationIssue != nil { evaluationIssue = nil }
  }

  private func resetLiveCard() {
    latestDiagnosticSample = nil
    readingGeneration = UUID()
    updateStability { $0 = CardStability() }
    rawText = ""
    clearResult()
  }

  private func missedReading(_ error: Error) {
    updateStability { $0.observe(nil, at: Date()) }
    if stability.signature == nil { clearResult() }
    showStatus(
      current == nil
        ? error.localizedDescription
        : "Rechecking the last verified card. Saving is paused. " + error.localizedDescription)
  }

  /// Applies a change to `stability`, announcing it only when what views read changes.
  @discardableResult
  private func updateStability<Value>(_ change: (inout CardStability) -> Value) -> Value {
    var next = stability
    let result = change(&next)
    if !next.looksSame(as: stability) { objectWillChange.send() }
    stability = next
    return result
  }

  /// Frames arrive up to five times a second; repeating the same message mustn't redraw every
  /// view.
  private func showStatus(_ message: String) {
    if status != message { status = message }
  }

  func setPlacementStatus(_ message: String) {
    if placementStatus != message { placementStatus = message }
  }

  func useText(_ text: String, confirmed: Bool) {
    guard enabled else { return }
    capture.setEnabled(false)
    enhancementContext = nil
    do {
      let artifact = try CardParser.parse(
        text, fiveStarsConfirmed: confirmed, rule: special ? .special : .ordinary)
      current = artifact
      updateStability { $0.useManual(artifact.signature) }
      rawText = text
      status = "Manual card. Live capture is stopped."
      issue = nil
      evaluate()
    } catch {
      issue = error.localizedDescription
      current = nil
      potential = nil
      allProfiles = []
      characterMatches = []
      verdict = nil
      evaluationIssue = nil
    }
  }

  @discardableResult
  func evaluate() -> Task<Void, Never>? {
    evaluation?.cancel()
    overviewFill?.cancel()
    overviewFill = nil
    potential = nil
    allProfiles = []
    characterMatches = []
    verdict = nil
    evaluationIssue = nil
    diagnosticRecommendation = nil
    recordDiagnosticDisplay()
    guard enabled, let current else { return nil }
    let generation = readingGeneration
    let profile = profile
    let pool = inventory.artifacts
    let scope = scope
    let excluded = linkedID ?? pool.first { $0.identity == current.identity }?.id
    let diagnosticKey = latestDiagnosticSample
    let includeOverview = assessmentMode == .profile
    let worker = Task.detached(priority: .userInitiated) {
      guard !Task.isCancelled else {
        return (
          nil as Result<Potential, Error>?, [(name: String, result: Potential)](),
          [CharacterMatch](), nil as Verdict?
        )
      }
      // One enumeration serves the profile, the presets, every role and the verdict. When it
      // fails, each of them reports the failure as it would alone.
      let outcomes = try? RollOutcomes(current)
      let result =
        Result {
          try Potential.evaluate(
            current, profile: profile, inventory: pool, scope: scope, excluding: excluded,
            outcomes: outcomes)
        }
      let overview =
        includeOverview
        ? Self.profileOverview(
          current, inventory: pool, scope: scope, excluding: excluded, outcomes: outcomes) : []
      let matches = CharacterAssessment.evaluate(
        current, inventory: pool, excluding: excluded, outcomes: outcomes)
      let verdict =
        Task.isCancelled
        ? nil
        : VerdictEngine.evaluate(
          current, matches: matches, inventory: pool, excluding: excluded, outcomes: outcomes)
      return (Optional(result), overview, matches, verdict)
    }
    evaluation = Task {
      let (result, overview, matches, verdict) = await withTaskCancellationHandler {
        await worker.value
      } onCancel: {
        worker.cancel()
      }
      guard !Task.isCancelled, enabled, readingGeneration == generation,
        self.current?.signature == current.signature, let result
      else { return }
      switch result {
      case .success(let value):
        potential = value
      case .failure(let error): evaluationIssue = error.localizedDescription
      }
      // An overview filled since this started, by switching to manual-profile mode, stays.
      if includeOverview { allProfiles = overview }
      characterMatches = matches
      self.verdict = verdict
      refreshDiagnosticRecommendation()
      if let diagnosticKey {
        capture.recordDiagnosticState(diagnosticState(), key: diagnosticKey)
      }
    }
    return evaluation
  }

  nonisolated private static func profileOverview(
    _ artifact: Artifact, inventory: [Artifact], scope: ComparisonScope, excluding: UUID?,
    outcomes: RollOutcomes?
  ) -> [(name: String, result: Potential)] {
    Profile.presets.compactMap { preset in
      guard !Task.isCancelled,
        let result = try? Potential.evaluate(
          artifact, profile: preset, inventory: inventory, scope: scope, excluding: excluding,
          outcomes: outcomes)
      else { return nil }
      return (preset.id, result)
    }
  }

  /// Character mode skips the preset overview, so switching to manual-profile mode fills it in
  /// without touching the character results on screen.
  private func fillProfileOverview() {
    overviewFill?.cancel()
    overviewFill = nil
    guard enabled, let current else { return }
    let generation = readingGeneration
    let pool = inventory.artifacts
    let scope = scope
    let excluded = linkedID ?? pool.first { $0.identity == current.identity }?.id
    let worker = Task.detached(priority: .userInitiated) {
      Self.profileOverview(
        current, inventory: pool, scope: scope, excluding: excluded,
        outcomes: try? RollOutcomes(current))
    }
    overviewFill = Task {
      let result = await withTaskCancellationHandler {
        await worker.value
      } onCancel: {
        worker.cancel()
      }
      guard !Task.isCancelled, enabled, readingGeneration == generation,
        assessmentMode == .profile, self.current?.signature == current.signature
      else { return }
      allProfiles = result
    }
  }

  func saveCurrent(copy: Bool = false) {
    guard canSaveCurrent, let current else { return }
    var next = inventory
    do {
      if let linkedID, !copy {
        try next.update(linkedID, with: current)
      } else {
        next.save(try current.withID(UUID()), allowIdenticalCopy: copy)
      }
      if next.artifacts != inventory.artifacts {
        try persist(next)
        evaluate()
      }
    } catch {
      issue = error.localizedDescription
      scanMode = false
    }
  }
  /// Pauses collection and hides the overlay while a scan clicks through the game.
  func beginScan() {
    isScanning = true
    linkedID = nil
    // Until the user turns it on again or relaunches: after the scan the game still shows the
    // piece it stopped at, which collection would save in an edit of its own, ahead of the
    // scan's Undo. Turning the reader off and on keeps it off.
    scanMode = false
    collectionPausedByScan = true
    updateOverlay?()
  }

  /// Saves what a scan read, all in one change that Undo reverses. Nil for a scan that read
  /// nothing.
  func finishScan(_ sweep: InventorySweep?) {
    isScanning = false
    updateOverlay?()
    guard let sweep else { return }
    var next = inventory
    let merge = next.mergeSweep(sweep.artifacts, covered: sweep.coveredLevels)
    do {
      if next.artifacts != inventory.artifacts {
        try persist(next)
        evaluate()
      }
      let listed = merge.unseen + merge.ambiguous.flatMap { [$0.added] + $0.earlier }
      lastScan = ScanReport(
        merge: merge, ending: sweep.ending, missed: sweep.missed.count,
        passed: sweep.others.count,
        cards: Dictionary(
          next.artifacts.filter { listed.contains($0.id) }.map { ($0.id, $0.signature) },
          uniquingKeysWith: { first, _ in first }))
    } catch {
      issue = "The scan's pieces weren't saved. \(error.localizedDescription)"
    }
  }

  /// Removes saved records together, as one change.
  func remove(_ ids: [UUID]) {
    var next = inventory
    for id in ids { next.remove(id) }
    do {
      try persist(next)
      if let linkedID, ids.contains(linkedID) { self.linkedID = nil }
      evaluate()
    } catch { issue = error.localizedDescription }
  }

  /// The Collect cards toggle, which is remembered for the next launch.
  func setCollectCards(_ value: Bool) {
    scanMode = value
    preferences.collectCards = value
    collectionPausedByScan = false
  }
  func link(_ artifact: Artifact) {
    scanMode = false
    linkedID = artifact.id
    status =
      "Linked to \(artifact.slot.label) +\(artifact.level). Select that piece, upgrade it, then Save to update."
    evaluate()
  }
  func remove(_ artifact: Artifact) {
    var next = inventory
    next.remove(artifact.id)
    do {
      try persist(next)
      if linkedID == artifact.id { linkedID = nil }
      evaluate()
    } catch { issue = error.localizedDescription }
  }
  func undo() {
    guard let previous = undoInventory else { return }
    do {
      try persist(previous)
      linkedID = nil
      evaluate()
    } catch { issue = error.localizedDescription }
  }
  private func persist(_ next: Inventory) throws {
    guard persistenceAvailable else {
      throw ArtifactError("Saving is disabled because the existing inventory could not be loaded.")
    }
    try next.write(to: file)
    undoInventory = inventory
    inventory = next
  }
  func importInventory() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.json]
    panel.canChooseDirectories = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      struct Format: Decodable { let format: String? }
      let data = try Data(contentsOf: url)
      let format = try JSONDecoder().decode(Format.self, from: data)
      let imported =
        try format.format == nil
        ? (artifacts: Inventory.read(from: url).artifacts, skipped: 0)
        : Inventory.importGOOD(data)
      var next = inventory
      try next.merge(imported.artifacts)
      try persist(next)
      evaluate()
      status =
        "Imported \(imported.artifacts.count) four- and five-star records; skipped \(imported.skipped) other rarities. Unfinished imports need ordinary-roll verification."
    } catch { issue = "Import failed without changing inventory: \(error.localizedDescription)" }
  }
  func exportInventory() {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.json]
    panel.nameFieldStringValue = "Loupe-inventory.json"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try inventory.write(to: url)
      status = "Inventory backup exported."
    } catch { issue = error.localizedDescription }
  }
  func stop() {
    setEnabled(false)
  }

  /// Saves the next frame of the game window and copies it, to paste into a chat or an issue.
  func saveSnapshot() {
    capture.saveSnapshot { [weak self] result in
      guard let self else { return }
      switch result {
      case .success(let saved):
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(saved.png, forType: .png)
        lastCapture = saved.url
        recordingStatus = "Snapshot saved and copied: \(saved.url.path)"
        banner?("Snapshot copied")
      case .failure(let error):
        recordingStatus = error.localizedDescription
        banner?(error.localizedDescription)
      }
    }
  }

  func toggleRecording() {
    if capture.isRecording {
      capture.stopRecording()
      return
    }
    capture.startRecording()
    if !capture.isRecording { banner?(recordingStatus) }
  }

  func showLastCapture() {
    guard let lastCapture else { return }
    NSWorkspace.shared.activateFileViewerSelecting([lastCapture])
  }

  /// Whether restarting now would interrupt the user: a capture, a recording, or a report.
  var isBusy: Bool {
    capture.isCapturing || isRecording || diagnostics.isPresented || diagnostics.isSaving
  }

  func reportIssue() {
    recordDiagnosticDisplay()
    let context = DiagnosticReportContext(
      appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        ?? "development",
      build: Bundle.main.object(forInfoDictionaryKey: "LoupeBuildFingerprint") as? String
        ?? "unpackaged",
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      pipelineVersion: "prepared-enhance-v1",
      settings: [
        "profile": profileName, "scope": scope.rawValue, "specialRolls": String(special),
        "scanMode": String(scanMode),
        "sampleRate":
          "5 frames/s captured; a changed frame is read at once while the reading changes, else at most 2 reads/s",
        "bufferSeconds": "10", "bufferMiB": "24",
        "overlayExpanded": String(overlayExpanded),
        "assessmentMode": assessmentMode.rawValue,
        "characterDataset": CharacterAssessment.datasetVersion,
        "tierCalibration": CharacterAssessment.calibrationVersion,
        "selectedRole": selectedMatch?.roleID ?? "none",
        "profileWeights": profile.weights.sorted { $0.key.rawValue < $1.key.rawValue }
          .map { "\($0.key.rawValue):\($0.value)" }.joined(separator: ","),
      ],
      replayLimitations: [
        "Inventory is partial: full-window anchor detection and star pixels are not retained.",
        "Initial confirmation history and verified Inventory context are not serialized. Supply context explicitly for parser replay.",
        "A sample frozen before its model callback can have a pending parser decision.",
        "Raw images are exact Vision inputs only when isExactOCRInput is true.",
        CharacterAssessment.coverageDescription,
      ])
    diagnostics.request(context: context) { [capture] in try await capture.freezeDiagnostics() }
  }

  func recordDiagnosticDisplay() {
    guard let key = latestDiagnosticSample, diagnostics.optedIn else { return }
    capture.recordDiagnosticState(diagnosticState(), key: key)
  }

  private func refreshDiagnosticRecommendation() {
    diagnosticRecommendation = nil
    let match = assessmentMode == .characters ? selectedMatch : nil
    let scoringProfile = assessmentMode == .characters ? match?.profile : profile
    if diagnostics.optedIn, let current, let result = displayedPotential, let scoringProfile {
      let excluded = linkedID ?? inventory.artifacts.first { $0.identity == current.identity }?.id
      diagnosticRecommendation = DiagnosticRecommendation.evaluated(
        current, result: result, profile: scoringProfile,
        pool: inventory.artifacts, scope: displayedScope, excluded: excluded, match: match)
    }
    recordDiagnosticDisplay()
  }

  private func diagnosticState() -> DiagnosticState {
    DiagnosticState(
      time: ProcessInfo.processInfo.systemUptime, displayedSampleID: displayedDiagnosticSample,
      readingState: stability.isVerified ? "verified" : current == nil ? "waiting" : "rechecking",
      displayedText: status + "\n" + recommendation + "\n" + assessmentDescription
        + (evaluationIssue.map { "\n" + $0 } ?? "") + (issue.map { "\n" + $0 } ?? ""),
      recommendation: diagnosticRecommendation,
      placement: diagnosticPlacement)
  }

  func chooseWindow() {
    guard enabled else { return }
    if !capture.enabled { capture.setEnabled(true) }
    capture.chooseWindow()
  }

  func setEnabled(_ value: Bool) {
    guard enabled != value else { return }
    enabled = value
    enhancementContext = nil
    scanMode = value && preferences.collectCards && !collectionPausedByScan
    linkedID = nil
    resetLiveCard()
    clearDiagnostics?()
    freshness?.invalidate()
    freshness = nil
    capture.setEnabled(value)
    if value { startFreshnessTimer() }
    updateOverlay?()
  }
}
