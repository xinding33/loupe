import AppKit
import Carbon
import LoupeCore
import Testing

@testable import Loupe

@MainActor
private final class TestCaptureConnection: CaptureConnection {
  let gate = FrameGate()
  var running = false
  var pauseStart = false
  var failStart = false
  var failStop = false
  private var entered = false
  private var started: CheckedContinuation<Void, Never>?
  private var resume: CheckedContinuation<Void, Never>?

  func start() async throws {
    entered = true
    started?.resume()
    started = nil
    if pauseStart { await withCheckedContinuation { resume = $0 } }
    if failStart { throw ArtifactError("Sharing permission unavailable") }
    running = true
  }
  func stop() async throws {
    if failStop { throw ArtifactError("macOS refused stop") }
    running = false
  }
  func invalidate() { gate.close() }
  func waitForStart() async {
    if !entered { await withCheckedContinuation { started = $0 } }
  }
  func finishStart() {
    resume?.resume()
    resume = nil
  }
}

@MainActor
@Test func runtimeDisableRejectsLateStartAndFrames() async {
  let runtime = CaptureRuntime()
  let connection = TestCaptureConnection()
  connection.pauseStart = true
  var ready = false
  runtime.ready = { ready = true }
  runtime.replace { _ in connection }
  let token = runtime.generation
  await connection.waitForStart()
  runtime.replace(with: nil)
  #expect(!connection.gate.isActive)
  #expect(!runtime.accepts(token))
  connection.finishStart()
  await runtime.waitForTransition()
  #expect(!connection.running)
  #expect(!ready)
}

@MainActor
@Test func runtimeRapidTogglesOnlyStartTheLatestSession() async {
  let runtime = CaptureRuntime()
  let old = TestCaptureConnection()
  let skipped = TestCaptureConnection()
  let latest = TestCaptureConnection()
  runtime.replace { _ in old }
  await runtime.waitForTransition()
  let oldToken = runtime.generation
  runtime.replace(with: nil)
  runtime.replace { _ in skipped }
  let skippedToken = runtime.generation
  runtime.replace(with: nil)
  runtime.replace { _ in latest }
  await runtime.waitForTransition()
  #expect(!old.running)
  #expect(!skipped.running)
  #expect(latest.running)
  #expect(!runtime.accepts(oldToken))
  #expect(!runtime.accepts(skippedToken))
  #expect(runtime.accepts(runtime.generation))
  runtime.replace(with: nil)
  await runtime.waitForTransition()
}

@MainActor
@Test func runtimeUnavailableCaptureFailsClosed() async {
  let runtime = CaptureRuntime()
  let denied = TestCaptureConnection()
  denied.failStart = true
  var failure: String?
  runtime.failed = { failure = $0.localizedDescription }
  runtime.replace { _ in denied }
  let token = runtime.generation
  await runtime.waitForTransition()
  #expect(failure == "Sharing permission unavailable")
  #expect(!runtime.accepts(token))
  #expect(!denied.gate.isActive)
  #expect(!denied.running)
}

@MainActor
@Test func runtimeDoesNotStartAnotherStreamWhenStopFails() async {
  let runtime = CaptureRuntime()
  let old = TestCaptureConnection()
  let next = TestCaptureConnection()
  runtime.replace { _ in old }
  await runtime.waitForTransition()
  old.failStop = true
  var failure: String?
  runtime.failed = { failure = $0.localizedDescription }
  runtime.replace { _ in next }
  await runtime.waitForTransition()
  #expect(!next.running)
  #expect(!runtime.accepts(runtime.generation))
  #expect(failure == "macOS refused stop")
  old.failStop = false
  runtime.replace(with: nil)
  await runtime.waitForTransition()
  #expect(!old.running)
}

private let runtimeCard = """
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

@MainActor
@Test func runtimeModelDisableClearsReadingsButPreservesInventoryAndSettings() async throws {
  let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
  let model = Model(inventoryFile: folder.appending(path: "inventory.json"))
  defer { try? FileManager.default.removeItem(at: folder) }
  let reading = CardReading(text: runtimeCard, stars: 5, confidence: 1)
  model.profileName = "ER"
  model.capture.receive?(.success(reading))
  model.capture.receive?(.success(reading))
  #expect(model.canSaveCurrent)
  model.saveCurrent()
  let saved = model.inventory.artifacts
  #expect(saved.count == 1)
  model.scanMode = true
  var diagnosticsCleared = false
  model.clearDiagnostics = { diagnosticsCleared = true }
  let pendingEvaluation = model.evaluate()
  model.setEnabled(false)
  await pendingEvaluation?.value
  model.capture.receive?(.success(reading))
  model.overlayExpanded = true
  model.useText(runtimeCard, confirmed: true)
  #expect(!model.enabled)
  #expect(!model.capture.enabled)
  #expect(model.current == nil)
  #expect(model.potential == nil)
  #expect(model.allProfiles.isEmpty)
  #expect(model.rawText.isEmpty)
  #expect(!model.canSaveCurrent)
  #expect(model.inventory.artifacts == saved)
  #expect(model.profileName == "ER")
  #expect(diagnosticsCleared)
  model.setEnabled(true)
  #expect(model.current == nil)
  #expect(model.status.contains("Choose game window"))
  let enhance = CardReading(text: "Enhance", stars: 0, confidence: 1, isEnhancement: true)
  model.capture.receive?(.success(enhance))
  #expect(model.status.contains("Inventory first"))
  #expect(model.current == nil)
  model.capture.receive?(.success(reading))
  #expect(!model.canSaveCurrent)
  model.capture.receive?(.success(reading))
  #expect(model.canSaveCurrent)
  model.setEnabled(false)
  await model.capture.stop()
}

@Test func runtimePlacementUsesLargestWindowAreaAndSafeBounds() throws {
  let first = OverlayDisplay(
    id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
    safeFrame: CGRect(x: 0, y: 40, width: 1440, height: 830), scale: 2)
  let second = OverlayDisplay(
    id: 2, frame: CGRect(x: 1440, y: -100, width: 1920, height: 1080),
    safeFrame: CGRect(x: 1440, y: -60, width: 1920, height: 1010), scale: 1)
  let placement = try #require(
    OverlayPlacement.resolve(
      window: CGRect(x: 1200, y: 100, width: 1000, height: 650), displays: [first, second],
      size: CGSize(width: 280, height: 140), offset: .zero))
  #expect(placement.display.id == 2)
  #expect(placement.panelFrame == CGRect(x: 3068, y: 798, width: 280, height: 140))
  let dragged = try #require(
    OverlayPlacement.resolve(
      window: first.frame, displays: [first, second],
      size: CGSize(width: 360, height: 630), offset: CGPoint(x: 5000, y: -5000)))
  #expect(dragged.display.id == 1)
  #expect(first.safeFrame.contains(dragged.panelFrame))
  #expect(dragged.panelFrame.origin == CGPoint(x: 1080, y: 40))
}

@Test func runtimePlacementHandlesVerticalDisplaysFullscreenAndRemoval() throws {
  let frame = OverlayPlacement.appKitFrame(
    CGRect(x: -1920, y: -1080, width: 1920, height: 1080), primaryTop: 900)
  #expect(frame == CGRect(x: -1920, y: 900, width: 1920, height: 1080))
  let display = OverlayDisplay(
    id: 7, frame: frame, safeFrame: frame.insetBy(dx: 10, dy: 25), scale: 2)
  let placement = try #require(
    OverlayPlacement.resolve(
      window: frame, displays: [display],
      size: CGSize(width: 360, height: 630), offset: .zero))
  #expect(display.safeFrame.contains(placement.panelFrame))
  #expect(
    OverlayPlacement.resolve(
      window: frame, displays: [], size: CGSize(width: 280, height: 140), offset: .zero) == nil)
  let small = OverlayDisplay(
    id: 8, frame: CGRect(x: 0, y: 0, width: 240, height: 200),
    safeFrame: CGRect(x: 0, y: 0, width: 240, height: 180), scale: 1)
  let clipped = try #require(
    OverlayPlacement.resolve(
      window: small.frame, displays: [small],
      size: CGSize(width: 360, height: 630), offset: .zero))
  #expect(clipped.panelFrame == small.safeFrame)
}

@Test func runtimeShortcutDefaultsAndInvalidInputs() throws {
  let expand = try OverlayShortcut("option+`")
  #expect(expand.keyCode == UInt32(kVK_ANSI_Grave))
  #expect(expand.modifiers == UInt32(optionKey))
  let enable = try OverlayShortcut("option+shift+`")
  #expect(enable.modifiers == UInt32(optionKey | shiftKey))
  #expect(try OverlayShortcut(" Control + K ") == OverlayShortcut("control+k"))
  #expect(throws: ArtifactError.self) { try OverlayShortcut("shift+a") }
  #expect(throws: ArtifactError.self) { try OverlayShortcut("option+option+a") }
  #expect(throws: ArtifactError.self) { try OverlayShortcut("option+unknown") }
  #expect(throws: ArtifactError.self) { try OverlayShortcut("option++a") }
}

@MainActor
private final class TestShortcutBackend: ShortcutBackend {
  var event: ((UInt32, Bool) -> Void)?
  var registered: Set<UInt32> = []
  var conflict = false
  func register(_ shortcut: OverlayShortcut, id: UInt32) throws {
    if conflict && id == 2 { throw ArtifactError("Already registered") }
    registered.insert(id)
  }
  func unregisterAll() { registered.removeAll() }
}

@MainActor
@Test func runtimeShortcutHeldKeysToggleOnceAndConflictsAreVisible() throws {
  let backend = TestShortcutBackend()
  let shortcuts = OverlayShortcuts(backend: backend)
  var expanded = false
  var enabled = true
  shortcuts.expand = { expanded.toggle() }
  shortcuts.toggleEnabled = { enabled.toggle() }
  try shortcuts.configure(expand: "option+`", enable: "option+shift+`")
  backend.event?(1, true)
  backend.event?(1, true)
  #expect(expanded)
  backend.event?(1, false)
  backend.event?(1, true)
  #expect(!expanded)
  backend.event?(2, true)
  backend.event?(2, true)
  #expect(!enabled)
  backend.event?(1, false)
  backend.event?(1, true)
  #expect(expanded)
  #expect(!enabled)
  #expect(throws: ArtifactError.self) {
    try shortcuts.configure(expand: "option+a", enable: "option+a")
  }
  backend.conflict = true
  #expect(throws: ArtifactError.self) {
    try shortcuts.configure(expand: "option+b", enable: "control+b")
  }
  #expect(backend.registered.isEmpty)
}
