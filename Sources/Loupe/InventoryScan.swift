import AppKit
import LoupeCore
import Vision

/// What the last inventory scan did, for the summary and review list under Saved inventory.
struct ScanReport: Equatable {
  let merge: SweepMerge
  let ending: InventoryStitch.Ending?
  /// Tiles whose card couldn't be read.
  let missed: Int
  /// One- to three-star pieces, which Loupe doesn't save.
  let passed: Int
  /// A vacant tile showed where the list ends.
  let endSeen: Bool
  /// Each listed record's card at the end of the scan. One changed since, by an upgrade saved to
  /// it, is no longer what the scan judged, so it drops out of the list.
  let cards: [UUID: String]

  var summary: String {
    var parts = ["Read \(merge.read) pieces: \(merge.alreadySaved) already saved"]
    if !merge.added.isEmpty { parts.append("\(merge.added.count) added") }
    if !merge.replaced.isEmpty {
      parts.append("\(merge.replaced.count) updated from a lower level")
    }
    var text = parts.joined(separator: ", ") + "."
    if passed > 0 { text += " Passed over \(passed) pieces below four stars." }
    if missed > 0 { text += " \(missed) tiles couldn't be read; select them by hand." }
    if let ending { text += " " + Self.describe(ending, endSeen: endSeen) }
    return text
  }

  static func describe(_ ending: InventoryStitch.Ending, endSeen: Bool) -> String {
    switch ending {
    case .belowMinimum: "Stopped at the first +0 piece."
    case .endOfList where endSeen: "Reached the end of the list."
    case .endOfList:
      "Stopped where the list stopped scrolling, with no empty tile to show its end. If more pieces follow, scan again."
    case .lostTrack(let reason): "Stopped: \(reason)"
    case .stopped: "Stopped before the end, so saved pieces below the last level read are kept."
    }
  }
}

/// Clicks through the game's Inventory grid, reading and saving each card. The only part of
/// Loupe besides auto-press that sends input to the game.
///
/// It clicks and scrolls only while the shared game window is frontmost and the point is on
/// it, not covered by another window. It stops for good on any key, click, scroll or mouse move
/// from the user, when the game leaves the front, or when the reader stops. Where it is in the
/// list it works out from the cards, as `InventoryStitch` describes; this class only looks,
/// clicks and scrolls.
@MainActor
final class InventoryScanner: ObservableObject {
  enum State: Equatable { case idle, waiting, running }

  /// Marks the events Loupe posts, so the input monitor can tell them from the user's.
  nonisolated static let marker: Int64 = 0x4C4F_5550

  @Published private(set) var state = State.idle
  @Published private(set) var progress = ""

  private let model: Model
  private var task: Task<Void, Never>?
  private var monitors: [Any] = []
  /// The capture session the scan reads from.
  private var session: UUID?
  /// Why the user's input stopped the scan, once it has.
  private var interruption: String?
  /// The game window, and the game, the scan posts to.
  private var context: ScanContext?
  /// The grid's columns and row spacing, from the first screen.
  private var known: InventoryGrid?
  /// The part of the window the list scrolls in, for telling whether it moved.
  private var view: ScanView?
  /// The left edge of the card beside the grid, the bottom of the bar above the grid, and the
  /// top of the bar under it.
  private var cardLeft = 0.0
  private var header = 0.0
  private var footer = 1.0
  /// The card panel, and the card it shows as of the last frame looked at.
  private var cardView: CardView?
  private var cardPicture: GrayImage?
  /// Tiles whose card was read so far, for the progress line.
  private var tilesRead = 0
  /// Where and when Loupe last moved the pointer, to tell its own move from the user's.
  private var lastPosted: (point: CGPoint, time: TimeInterval)?
  private let source = CGEventSource(stateID: .hidSystemState)
  /// The steps of the scan under way, saved beside the inventory when it ends.
  private var scanLog: [String] = []
  private var scanStart: TimeInterval?
  /// Scrolls so far, numbering the pictures saved for each.
  private var scrolls = 0

  init(model: Model) {
    self.model = model
  }

  var isActive: Bool { state != .idle }

  func toggle() {
    if isActive { stop("Scan stopped.") } else { start() }
  }

  func start() {
    guard state == .idle else { return }
    guard model.enabled, model.capture.isCapturing, let windowID = model.capture.selectedWindowID
    else {
      report("Choose the game window first, then scan.")
      return
    }
    guard AXIsProcessTrusted() else {
      // The value of kAXTrustedCheckOptionPrompt, which Swift 6 won't read: a global var.
      _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
      report(
        "Scanning clicks in the game, so it needs Accessibility access. Allow Loupe, then scan again."
      )
      return
    }
    guard let owner = Self.owner(of: windowID) else {
      report("The shared window is gone. Choose the game window again.")
      return
    }
    interruption = nil
    state = .waiting
    progress = "Switch to the game's Inventory. The scan starts once the game is in front."
    task = Task { [weak self] in await self?.run(windowID: windowID, target: owner) }
  }

  func stop(_ reason: String) {
    guard state != .idle else { return }
    if interruption == nil { interruption = reason }
    task?.cancel()
  }

  private func report(_ message: String) {
    progress = message
    model.banner?(message)
  }

  // MARK: The scan

  private func run(windowID: CGWindowID, target: AutoPressTarget) async {
    defer {
      removeMonitor()
      model.capture.setScanning(false)
      context = nil
      state = .idle
      task = nil
    }
    guard await waitForGame(target) else {
      progress = interruption ?? "The game didn't come to the front, so the scan didn't start."
      return
    }
    state = .running
    // The scan belongs to one capture session: a new stream, even of the same window, ends it.
    guard let session = model.capture.sessionID, model.capture.selectedWindowID == windowID else {
      progress = "The shared window changed, so the scan didn't start."
      return
    }
    self.session = session
    // The scan reads its own frames, faster than the live reader, which pauses meanwhile.
    model.capture.setScanning(true)
    installMonitor()
    model.beginScan()
    model.banner?("Scanning Inventory. Move the mouse to stop.")
    progress = "Scanning. Move the mouse or press a key to stop."
    guard let first = await firstScreen() else {
      model.finishScan(nil)
      report(
        "Couldn't find the Inventory grid. Open Inventory with an artifact selected, then scan.")
      return
    }
    context = ScanContext(windowID: windowID, target: target)
    known = first.grid
    view = first.view
    cardLeft = first.cardLeft
    header = first.header
    footer = first.footer
    cardView = first.card
    cardPicture = first.cardPicture
    tilesRead = 0
    scanStart = ProcessInfo.processInfo.systemUptime
    scrolls = 0
    try? FileManager.default.removeItem(at: model.scanPicturesFolder)
    try? FileManager.default.createDirectory(
      at: model.scanPicturesFolder, withIntermediateDirectories: true)
    scanLog = [
      "grid \(first.grid.columns.count)x\(first.grid.rows.count) row pitch "
        + format(first.grid.rowPitch) + " header " + format(first.header) + " footer "
        + format(first.footer)
    ]
    // Every levelled piece: the list is sorted by level, so the first +0 ends it.
    let (stitch, error) = await InventoryStitch.scan(self, minimumLevel: 1)
    let failure: String? =
      if let error, !(error is CancellationError) { error.localizedDescription } else { nil }
    model.finishScan(stitch)
    log(
      "end \(stitch.ending.map { ScanReport.describe($0, endSeen: stitch.endSeen) } ?? "-") read "
        + "\(stitch.artifacts.count) passed \(stitch.others) missed \(stitch.missed) "
        + "covered \(stitch.coveredLevels.sorted())" + (failure.map { " (\($0))" } ?? ""))
    try? scanLog.joined(separator: "\n").appending("\n").write(
      to: model.scanLogFile, atomically: true, encoding: .utf8)
    let summary = model.lastScan?.summary ?? ""
    // The user's own stop says why better than the error it caused.
    if let reason = interruption ?? failure, stitch.ending == .stopped {
      progress = reason + " " + summary
      model.banner?("Scan stopped")
    } else {
      progress = summary
      model.banner?("Scan finished: \(stitch.artifacts.count) read")
    }
  }

  /// A grid picture, as a PGM file anything can open.
  private func save(_ picture: GrayImage, as name: String) {
    var data = Data("P5\n\(picture.width) \(picture.height)\n255\n".utf8)
    data.append(contentsOf: picture.pixels)
    try? data.write(to: model.scanPicturesFolder.appending(path: name + ".pgm"))
  }

  private func format(_ value: Double?) -> String {
    value.map { String(format: "%.4f", $0) } ?? "none"
  }

  private func describe(_ card: InventoryStitch.Card?) -> String {
    switch card {
    case .read(let artifact): "\(artifact.rarity)* +\(artifact.level) \(artifact.slot.rawValue)"
    case .other(_, let level): "low rarity +\(level)"
    case .unread: "unread"
    case nil: "unchanged"
    }
  }

  /// Waits up to a minute for the game to be in front for a second.
  private func waitForGame(_ target: AutoPressTarget) async -> Bool {
    var since: TimeInterval?
    let deadline = ProcessInfo.processInfo.systemUptime + 60
    while !Task.isCancelled, ProcessInfo.processInfo.systemUptime < deadline {
      let now = ProcessInfo.processInfo.systemUptime
      if AutoPresser.focus(target) == .target {
        since = since ?? now
        if now - since! >= 1 { return true }
      } else {
        since = nil
      }
      try? await Task.sleep(for: .milliseconds(200))
    }
    return false
  }

  /// Throws once the reader stops sharing the game window the scan started on.
  private func checkSharing() throws {
    guard model.enabled, model.capture.isCapturing, model.capture.sessionID == session else {
      throw InputError.captureStopped
    }
  }

  // MARK: Clicking tiles

  /// A tile clicked: the card it brought up, read in the background, or none when the card
  /// didn't change.
  private struct Shot {
    let reading: Task<(card: InventoryStitch.Card, note: String), Never>?
    /// How long the new card took to show and hold still.
    let settled: TimeInterval?
  }

  /// Clicks a tile and waits for its card: a picture of the card panel that differs from the
  /// one before the click, held still across two frames. That frame is read in the background.
  /// A card that doesn't change in a second and a half is the one before: the click didn't land,
  /// the tile was selected already, or it's an identical copy of the last.
  private func shot(_ point: CGPoint, label: Int?, _ context: ScanContext) async throws -> Shot {
    guard let cardView else { return Shot(reading: nil, settled: nil) }
    let before = cardPicture
    let pressed = try await click(point, context)
    var changing: (image: CGImage, picture: GrayImage)?
    while ProcessInfo.processInfo.systemUptime < pressed + 1.5 {
      try Task.checkCancellation()
      guard let image = await model.capture.nextFrame(timeout: 0.5),
        let picture = cardView.picture(of: image)
      else {
        try await Task.sleep(for: .milliseconds(50))
        continue
      }
      let new = before.flatMap { GrayImage.largestBlockDifference($0, picture, block: 6) }.map {
        $0 > 20
      }
      guard new ?? true else {
        changing = nil
        continue
      }
      if let changing,
        (GrayImage.largestBlockDifference(changing.picture, picture, block: 6) ?? 99) < 10
      {
        cardPicture = picture
        return Shot(
          reading: Task.detached(priority: .userInitiated) { Self.read(image, label: label) },
          settled: ProcessInfo.processInfo.systemUptime - pressed)
      }
      changing = (image, picture)
    }
    // A new card that never held still is read as it last looked.
    guard let changing else { return Shot(reading: nil, settled: nil) }
    cardPicture = changing.picture
    let image = changing.image
    return Shot(
      reading: Task.detached(priority: .userInitiated) { Self.read(image, label: label) },
      settled: nil)
  }

  /// The card in a frame, with why it couldn't be read. Four- and five-star cards are parsed as
  /// pieces; one to three stars are passed over, unless the level is past what the stars allow,
  /// which means the stars were miscounted. A card that doesn't parse at the level read on it is
  /// tried at `label`, the level read under its tile: the substats' rolls must fit that level,
  /// so a misread digit can't pass for a level the card doesn't have.
  nonisolated static func read(_ image: CGImage, label: Int? = nil) -> (
    card: InventoryStitch.Card, note: String
  ) {
    let reading: CardReading
    do { reading = try CardOCR.readInventory(image) } catch {
      return (.unread, error.localizedDescription)
    }
    // The card's lines up to its set name, for the log when it fails. Lines further down can
    // hold the UID.
    let lines = reading.text.components(separatedBy: .newlines)
    let setLine =
      lines.firstIndex { CardParser.tidied($0).hasSuffix(":") } ?? min(9, lines.count - 1)
    let text = lines.prefix(setLine + 1).filter { !$0.localizedCaseInsensitiveContains("UID") }
      .joined(separator: " / ")
    guard reading.confidence >= 0.65 else {
      return (.unread, String(format: "confidence %.2f: ", reading.confidence) + text)
    }
    if (1...3).contains(reading.stars) {
      guard let card = CardParser.glance(reading.text, stars: reading.stars) else {
        return (.unread, "\(reading.stars) stars counted: " + text)
      }
      return (.other(key: card.key, level: card.level), "")
    }
    do {
      let card = try CardParser.parseScanned(reading.text, stars: reading.stars, label: label)
      return (.read(card.artifact), card.note)
    } catch {
      return (.unread, error.localizedDescription + ": " + text)
    }
  }

  // MARK: Reading the grid

  /// The first screen: where the card starts, so labels right of it aren't taken as tiles,
  /// where the bar above the grid ends, and where the bar under it starts.
  private func firstScreen() async -> (
    grid: InventoryGrid, view: ScanView, cardLeft: Double, header: Double, footer: Double,
    card: CardView, cardPicture: GrayImage?
  )? {
    guard let image = await model.capture.nextFrame(),
      let left = await Task.detached(operation: { GridReader.cardLeft(in: image) }).value,
      let second = await model.capture.nextFrame()
    else { return nil }
    let labels = await Task.detached {
      GridReader.labels(in: image, left: left) + GridReader.labels(in: second, left: left)
    }.value
    // Without the bar above, a row cut off under it could pass for whole, and a click on it land
    // on the bar. Without the bar below, its pale buttons could pass for a row's strips, and
    // their tiles for the end of the list.
    guard let header = GridReader.header(labels), let footer = GridReader.footer(labels),
      let lattice = InventoryGrid.detect(labels)
    else { return nil }
    // Rows whose labels weren't read, from the strips under them.
    let strips = GridReader.strips(in: second, columns: lattice, above: footer)
    let found = InventoryGrid.detect(labels, known: lattice, strips: strips) ?? lattice
    guard found.rows.count >= 2, let view = ScanView(found, below: header, strips: strips)
    else { return nil }
    let card = CardView(left: left)
    return (found, view, left, header, footer, card, card.picture(of: second))
  }

  /// The grid's picture once it holds still: two frames in a row with nothing moved, and the
  /// frame.
  private func settled(_ view: ScanView) async -> (image: CGImage, picture: GrayImage)? {
    try? await Task.sleep(for: .milliseconds(300))
    guard var image = await model.capture.nextFrame(), var picture = view.picture(of: image)
    else { return nil }
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    while ProcessInfo.processInfo.systemUptime < deadline {
      guard let next = await model.capture.nextFrame(), let nextPicture = view.picture(of: next)
      else { return nil }
      if GrayImage.verticalShift(from: picture, to: nextPicture, within: -4...4) == 0 {
        return (next, nextPicture)
      }
      image = next
      picture = nextPicture
    }
    return (image, picture)
  }

  /// The grid's picture as it is now, with the pointer moved to `point` first.
  private func picture(at point: CGPoint, view: ScanView, _ context: ScanContext) async throws
    -> GrayImage?
  {
    post(.mouseMoved, at: try target(point, context))
    try await Task.sleep(for: .milliseconds(150))
    // A frame from before the move may be on its way.
    _ = await model.capture.nextFrame()
    return await model.capture.nextFrame().flatMap { view.picture(of: $0) }
  }

  // MARK: Input

  private struct ScanContext {
    let windowID: CGWindowID
    let target: AutoPressTarget
  }

  private enum InputError: LocalizedError {
    case notInFront, windowGone, captureStopped
    case covered(String)
    case interrupted
    var errorDescription: String? {
      switch self {
      case .notInFront: "Stopped: the game left the front."
      case .windowGone: "Stopped: the game window is gone."
      case .captureStopped: "Stopped: the reader stopped sharing the game window."
      case .covered(let owner): "Stopped: \(owner) covers the Inventory grid."
      case .interrupted: "Stopped."
      }
    }
  }

  /// The screen point for a point in the window, after checking it's safe to post there. Asked
  /// again right before every event, with nothing awaited in between.
  private func target(_ point: CGPoint, _ context: ScanContext) throws -> CGPoint {
    guard !Task.isCancelled, state == .running else { throw InputError.interrupted }
    guard model.enabled, model.capture.isCapturing,
      model.capture.selectedWindowID == context.windowID, model.capture.sessionID == session
    else { throw InputError.captureStopped }
    guard AutoPresser.focus(context.target) == .target else { throw InputError.notInFront }
    guard let bounds = Self.bounds(of: context.windowID) else { throw InputError.windowGone }
    let screen = CGPoint(
      x: bounds.minX + point.x * bounds.width, y: bounds.minY + point.y * bounds.height)
    if let cover = Self.cover(at: screen, window: context.windowID) {
      throw InputError.covered(cover)
    }
    return screen
  }

  /// Clicks a tile. Returns when the button went down.
  private func click(_ point: CGPoint, _ context: ScanContext) async throws -> TimeInterval {
    post(.mouseMoved, at: try target(point, context))
    try? await Task.sleep(for: .milliseconds(60))
    // The window may have moved while waiting, so press where the check just passed.
    let screen = try target(point, context)
    let pressed = ProcessInfo.processInfo.systemUptime
    post(.leftMouseDown, at: screen)
    try? await Task.sleep(for: .milliseconds(50))
    // Releases the press just made, even after a stop: a button left down would be worse.
    post(.leftMouseUp, at: screen)
    return pressed
  }

  /// Turns the wheel over the grid, a line at a time, positive as `CGEvent` counts up.
  private func scroll(_ lines: Int, at point: CGPoint, _ context: ScanContext) async throws {
    post(.mouseMoved, at: try target(point, context))
    try? await Task.sleep(for: .milliseconds(60))
    for _ in 0..<abs(lines) {
      let screen = try target(point, context)
      if let lastPosted, lastPosted.point != screen { post(.mouseMoved, at: screen) }
      guard
        let event = CGEvent(
          scrollWheelEvent2Source: source, units: .line, wheelCount: 1,
          wheel1: lines > 0 ? 1 : -1, wheel2: 0, wheel3: 0)
      else { continue }
      event.location = screen
      mark(event, at: screen)
      event.post(tap: .cghidEventTap)
      try? await Task.sleep(for: .milliseconds(30))
    }
  }

  private func post(_ type: CGEventType, at point: CGPoint) {
    guard
      let event = CGEvent(
        mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
    else { return }
    event.flags = []
    mark(event, at: point)
    event.post(tap: .cghidEventTap)
  }

  private func mark(_ event: CGEvent, at point: CGPoint) {
    event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
    lastPosted = (point, ProcessInfo.processInfo.systemUptime)
  }

  /// Watches input to other apps, and to Loupe, which a global monitor doesn't see.
  private func installMonitor() {
    removeMonitor()
    // Releases too: a button or key held down before the scan started ends it when let go.
    let events: NSEvent.EventTypeMask = [
      .keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown,
      .rightMouseUp, .otherMouseDown, .otherMouseUp, .mouseMoved, .leftMouseDragged,
      .rightMouseDragged, .otherMouseDragged, .scrollWheel,
    ]
    if let global = NSEvent.addGlobalMonitorForEvents(
      matching: events,
      handler: { [weak self] event in MainActor.assumeIsolated { self?.userInput(event) } })
    {
      monitors.append(global)
    }
    if let local = NSEvent.addLocalMonitorForEvents(
      matching: events,
      handler: { [weak self] event in
        MainActor.assumeIsolated { self?.userInput(event) }
        return event
      })
    {
      monitors.append(local)
    }
  }

  private func removeMonitor() {
    for monitor in monitors { NSEvent.removeMonitor(monitor) }
    monitors = []
  }

  /// Stops on anything the user does. Only Loupe's marked events pass, and a pointer move that
  /// lands exactly where Loupe just moved it, which the system can report unmarked.
  private func userInput(_ event: NSEvent) {
    guard state == .running, let cgEvent = event.cgEvent else { return }
    if cgEvent.getIntegerValueField(.eventSourceUserData) == Self.marker { return }
    if event.type == .mouseMoved, let lastPosted {
      let location = cgEvent.location
      let same = hypot(location.x - lastPosted.point.x, location.y - lastPosted.point.y) < 0.5
      if same && ProcessInfo.processInfo.systemUptime - lastPosted.time < 0.2 { return }
    }
    let key = [.keyDown, .keyUp, .flagsChanged].contains(event.type)
    stop(key ? "Stopped: you pressed a key." : "Stopped: you used the mouse.")
  }

  // MARK: Windows

  /// The game as auto-press would target it: the app, or this run of a process with no bundle.
  private static func owner(of window: CGWindowID) -> AutoPressTarget? {
    guard
      let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, window) as? [[String: Any]])?
        .first,
      let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
    else { return nil }
    let app = NSRunningApplication(processIdentifier: pid)
    let name = info[kCGWindowOwnerName as String] as? String ?? "the game"
    return AutoPressTarget(
      bundleID: app?.bundleIdentifier, pid: pid, start: { ProcessStart.of(pid) }, name: name)
  }

  private static func bounds(of window: CGWindowID) -> CGRect? {
    guard
      let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, window) as? [[String: Any]])?
        .first,
      let bounds = info[kCGWindowBounds as String] as? [String: Any]
    else { return nil }
    return CGRect(dictionaryRepresentation: bounds as CFDictionary)
  }

  /// The owner of a window above the game at `point`, or nil when the game is on top there.
  /// Loupe's own click-through windows, such as the banner, don't count. The game's other
  /// windows do: one could be a dialog over the grid.
  private static func cover(at point: CGPoint, window: CGWindowID) -> String? {
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else { return "Another window" }
    let own = ProcessInfo.processInfo.processIdentifier
    for info in windows {
      guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
        let boundsInfo = info[kCGWindowBounds as String] as? [String: Any],
        let bounds = CGRect(dictionaryRepresentation: boundsInfo as CFDictionary),
        bounds.contains(point)
      else { continue }
      if number == window { return nil }
      if (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue == 0 { continue }
      let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
      if pid == own,
        NSApp.windows.first(where: { $0.windowNumber == Int(number) })?.ignoresMouseEvents ?? false
      {
        continue
      }
      return info[kCGWindowOwnerName as String] as? String ?? "Another window"
    }
    return "Another window"
  }
}

extension InventoryScanner: InventoryStitchGame {
  /// The rows the grid shows whole, between the bars above and below it, as
  /// `InventoryGrid.wholeRows` tells.
  func screen() async throws -> InventoryStitch.Screen? {
    try checkSharing()
    guard let known, let view, let (image, _) = await settled(view) else { return nil }
    let left = cardLeft
    let footer = footer
    let (labels, strips) = await Task.detached {
      (
        GridReader.labels(in: image, left: left),
        GridReader.strips(in: image, columns: known, above: footer)
      )
    }.value
    guard let found = InventoryGrid.detect(labels, known: known, strips: strips) else {
      log("screen: no grid")
      return nil
    }
    let grid = GridReader.markVacant(found, in: image, strips: strips)
    let whole = grid.wholeRows(strips: strips, header: header, footer: footer)
    log("screen: whole rows at " + whole.map { format(grid.rows[$0].y) }.joined(separator: " "))
    return InventoryStitch.Screen(
      rows: whole.map { row in
        grid.columns.indices.map { column in
          InventoryStitch.Tile(
            point: grid.tile(row: row, column: column), label: grid.rows[row].levels[column],
            vacant: grid.rows[row].vacant[column])
        }
      })
  }

  /// Clicks each tile, reading its card in the background while the next is clicked. A tile
  /// whose card didn't change shows the card before it: an identical copy, or a click that
  /// didn't land. It's clicked again after a tile with another card, and again after a tile
  /// with a third if need be, since its card can't match both: a copy then shows, and a tile
  /// that still doesn't is left unread.
  func read(_ tiles: [InventoryStitch.Tile]) async throws -> [InventoryStitch.Card] {
    guard let context else { throw InputError.interrupted }
    try checkSharing()
    var shots: [Shot] = []
    for tile in tiles { shots.append(try await shot(tile.point, label: tile.label, context)) }
    var cards: [InventoryStitch.Card?] = []
    for (index, shot) in shots.enumerated() {
      var card: InventoryStitch.Card?
      var note = ""
      if let reading = shot.reading { (card, note) = await reading.value }
      log(
        "tile \(index) label \(tiles[index].label.map { "+\($0)" } ?? "-") card "
          + describe(card) + (note.isEmpty ? "" : " (\(note))")
          + (shot.settled.map { String(format: " settled %.2fs", $0) } ?? ""))
      cards.append(card)
    }
    var keyed: [Int] = []
    for index in cards.indices {
      guard let key = cards[index]?.key, !keyed.contains(where: { cards[$0]?.key == key })
      else { continue }
      keyed.append(index)
    }
    for index in cards.indices where cards[index] == nil {
      var card = InventoryStitch.Card.unread
      for other in keyed.prefix(2) where other != index {
        _ = try await shot(tiles[other].point, label: tiles[other].label, context)
        let again = try await shot(tiles[index].point, label: tiles[index].label, context)
        guard let reading = again.reading else { continue }
        card = await reading.value.card
        break
      }
      log("tile \(index) again: \(describe(card))")
      cards[index] = card
    }
    try checkSharing()
    tilesRead += tiles.count
    progress = "Scanning: \(tilesRead) tiles read. Move the mouse to stop."
    return cards.map { $0 ?? .unread }
  }

  /// Turns the wheel over the grid and tells whether the grid moved, from pictures taken just
  /// before and once it holds still: on a still grid only a tile's pulsing highlight changes.
  func scroll(_ lines: Int) async throws -> Bool {
    guard let context, let view else { throw InputError.interrupted }
    try checkSharing()
    let before = try await picture(at: view.center, view: view, context)
    try await scroll(lines, at: view.center, context)
    guard let after = await settled(view)?.picture else { return false }
    scrolls += 1
    if let before { save(before, as: "\(scrolls) before") }
    save(after, as: "\(scrolls) after")
    let difference = before.flatMap { GrayImage.meanDifference($0, after) }
    let moved = difference.map { $0 >= 4 } ?? true
    log(
      "scroll \(scrolls): \(lines) lines, \(moved ? "moved" : "still")"
        + (difference.map { String(format: " (difference %.1f)", $0) } ?? ""))
    return moved
  }

  func pause(_ seconds: Double) async throws {
    try await Task.sleep(for: .seconds(seconds))
  }

  func log(_ line: String) {
    let time = ProcessInfo.processInfo.systemUptime - (scanStart ?? 0)
    scanLog.append(String(format: "%7.1f ", time) + line)
  }
}

/// The part of the window the grid scrolls in, as a small grayscale picture for telling whether
/// it moved, and where to point the wheel.
struct ScanView {
  /// Window coordinates from the top left.
  let area: CGRect
  let rowPitch: Double
  static let size = (width: 120, height: 240)

  /// The grid's rows, only as far as the list shows them: below `header`, the bar above the
  /// grid that doesn't scroll, and down to the last of `strips` shown whole, above where the
  /// list fades out. A picture reaching past either compares what stays put, or what the fade
  /// changes, with what scrolled.
  init?(_ grid: InventoryGrid, below header: Double? = nil, strips: [Double] = []) {
    guard let first = grid.columns.first, let last = grid.columns.last,
      let top = grid.rows.first?.y, let bottom = grid.rows.last?.y
    else { return nil }
    let x = first - 0.5 * grid.columnPitch
    let y = max(top - 0.6 * grid.rowPitch, header ?? 0)
    var end = bottom + 0.03
    let shown = strips.filter { strip in
      grid.rows.contains { abs($0.y - strip) < 0.2 * grid.rowPitch }
    }
    if let lastStrip = shown.max(), lastStrip > y { end = min(end, lastStrip + 0.012) }
    area = CGRect(x: x, y: y, width: last + 0.5 * grid.columnPitch - x, height: end - y)
    rowPitch = grid.rowPitch
    guard area.width > 0, area.height > 0 else { return nil }
  }

  var center: CGPoint { CGPoint(x: area.midX, y: area.midY) }

  func picture(of image: CGImage) -> GrayImage? {
    Self.picture(of: image, area: area, size: Self.size)
  }

  /// `area` of `image`, in grays, scaled to `size`.
  static func picture(of image: CGImage, area: CGRect, size: (width: Int, height: Int))
    -> GrayImage?
  {
    let rect = CGRect(
      x: area.minX * Double(image.width), y: area.minY * Double(image.height),
      width: area.width * Double(image.width), height: area.height * Double(image.height)
    ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard !rect.isEmpty, let crop = image.cropping(to: rect) else { return nil }
    let (width, height) = size
    var pixels = [UInt8](repeating: 0, count: width * height)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
          bitmapInfo: CGImageAlphaInfo.none.rawValue)
      else { return false }
      context.interpolationQuality = .medium
      context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return drawn ? GrayImage(width: width, height: height, pixels: pixels) : nil
  }

}

/// The selected artifact's card, beside the grid, for telling when a click brought up another.
struct CardView {
  /// Window coordinates from the top left.
  let area: CGRect
  /// Fine enough that one changed digit fills most of a block.
  static let size = (width: 240, height: 480)

  /// The card whose slot line starts just right of `left`.
  init(left: Double) {
    area = CGRect(x: left, y: 0.14, width: min(0.36, 0.99 - left), height: 0.74)
  }

  func picture(of image: CGImage) -> GrayImage? {
    ScanView.picture(of: image, area: area, size: Self.size)
  }
}

/// Vision passes over the Inventory screen.
enum GridReader {
  /// The left edge of the selected artifact's card, found from its slot line, in window
  /// coordinates. Nil without exactly one card.
  static func cardLeft(in image: CGImage) -> Double? {
    let slots = [
      "flower of life", "plume of death", "sands of eon", "goblet of eonothem", "circlet of logos",
    ]
    let anchors = recognize(image).filter { label in
      slots.contains { label.text.lowercased().contains($0) }
    }
    guard anchors.count == 1, let anchor = anchors.first else { return nil }
    return anchor.bounds.minX - 0.02
  }

  /// The text left of the card. Reading only that part finds every level label, where a pass
  /// over the whole window misses some.
  static func labels(in image: CGImage, left: Double) -> [GridLabel] {
    let area = CGRect(x: 0, y: 0.08, width: max(0.05, left), height: 0.92)
    let rect = CGRect(
      x: 0, y: area.minY * Double(image.height), width: area.width * Double(image.width),
      height: area.height * Double(image.height)
    ).integral
    guard let crop = image.cropping(to: rect) else { return [] }
    return recognize(crop).map { label in
      GridLabel(
        text: label.text,
        bounds: CGRect(
          x: area.minX + label.bounds.minX * area.width,
          y: area.minY + label.bounds.minY * area.height,
          width: label.bounds.width * area.width, height: label.bounds.height * area.height))
    }
  }

  /// The bottom of the bar above the grid, "Show 5-star Artifacts in the order of when they
  /// were obtained", which stays put as the list scrolls; nil when it wasn't read.
  static func header(_ labels: [GridLabel]) -> Double? {
    labels.filter {
      $0.text.localizedCaseInsensitiveContains("obtained")
        || $0.text.localizedCaseInsensitiveContains("5-star Artifacts")
    }.map { Double($0.bounds.maxY) + 0.008 }.max()
  }

  /// The top of the bar under the grid, whose "Lock Assistance" and "Salvage" buttons are the
  /// pale cream of a label strip; nil when neither was read. The buttons start a little above
  /// their text, and Vision's bounds take in more or less of them.
  static func footer(_ labels: [GridLabel]) -> Double? {
    labels.filter {
      $0.text.localizedCaseInsensitiveContains("Lock Assistance")
        || $0.text.localizedCaseInsensitiveContains("Salvage")
    }.map { Double($0.bounds.minY) - 0.015 }.min()
  }

  /// The middles of the pale strips under the tiles of `grid`'s columns, from how much of each
  /// line of pixels across them is strip-colored, in window coordinates. Only above `footer`,
  /// the bar under the grid.
  static func strips(in image: CGImage, columns grid: InventoryGrid, above footer: Double)
    -> [Double]
  {
    guard let first = grid.columns.first, let last = grid.columns.last else { return [] }
    let top = 0.1
    let bottom = min(0.95, footer)
    let rect = CGRect(
      x: (first - 0.5 * grid.columnPitch) * Double(image.width), y: top * Double(image.height),
      width: (last - first + grid.columnPitch) * Double(image.width),
      height: (bottom - top) * Double(image.height)
    ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard !rect.isEmpty, let crop = image.cropping(to: rect) else { return [] }
    let width = crop.width
    let height = crop.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return [] }
    // The middle three fifths of each tile's width, where its strip is.
    let spans = grid.columns.map { column -> Range<Int> in
      let low = Int(((column - 0.3 * grid.columnPitch) * Double(image.width) - rect.minX).rounded())
      let high = Int(
        ((column + 0.3 * grid.columnPitch) * Double(image.width) - rect.minX).rounded())
      return max(0, low)..<min(width, max(low, high))
    }
    let total = spans.reduce(0) { $0 + $1.count }
    guard total > 0 else { return [] }
    let share = (0..<height).map { y -> Double in
      var cream = 0
      for span in spans {
        for x in span {
          let i = (y * width + x) * 4
          if abs(Int(bytes[i]) - 233) < 14 && abs(Int(bytes[i + 1]) - 229) < 14
            && abs(Int(bytes[i + 2]) - 221) < 14
          {
            cream += 1
          }
        }
      }
      return Double(cream) / Double(total)
    }
    return InventoryGrid.strips(
      share, top: rect.minY / Double(image.height), step: 1 / Double(image.height))
  }

  /// Marks the tiles with no level label and none of the pale strip the label sits on, about
  /// three quarters of a tile's strip and none of the background behind the grid.
  /// Only rows whose strip shows whole, among `strips`, are judged: in a row cut off by the
  /// edge of the grid, a tile's strip can be out of sight.
  static func markVacant(_ grid: InventoryGrid, in image: CGImage, strips: [Double])
    -> InventoryGrid
  {
    var grid = grid
    for row in grid.rows.indices
    where strips.contains(where: { abs($0 - grid.rows[row].y) < 0.2 * grid.rowPitch }) {
      for column in grid.columns.indices where grid.rows[row].levels[column] == nil {
        let area = CGRect(
          x: grid.columns[column] - 0.3 * grid.columnPitch, y: grid.rows[row].y - 0.009,
          width: 0.6 * grid.columnPitch, height: 0.018)
        if let share = stripShare(in: image, area: area) {
          grid.rows[row].vacant[column] = share < 0.2
        }
      }
    }
    return grid
  }

  /// How much of `area` is the pale cream of a tile's level strip. Nil off the picture.
  static func stripShare(in image: CGImage, area: CGRect) -> Double? {
    let rect = CGRect(
      x: area.minX * Double(image.width), y: area.minY * Double(image.height),
      width: area.width * Double(image.width), height: area.height * Double(image.height)
    ).integral
    guard rect.minX >= 0, rect.minY >= 0, rect.maxX <= Double(image.width),
      rect.maxY <= Double(image.height), rect.width > 0, rect.height > 0,
      let crop = image.cropping(to: rect)
    else { return nil }
    let width = crop.width
    let height = crop.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    var cream = 0
    for pixel in stride(from: 0, to: bytes.count, by: 4) {
      if abs(Int(bytes[pixel]) - 233) < 14 && abs(Int(bytes[pixel + 1]) - 229) < 14
        && abs(Int(bytes[pixel + 2]) - 221) < 14
      {
        cream += 1
      }
    }
    return Double(cream) / Double(width * height)
  }

  /// Text in `image`, with bounds from its top left, 0 to 1.
  private static func recognize(_ image: CGImage) -> [GridLabel] {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
    return (request.results ?? []).compactMap { observation in
      guard let text = observation.topCandidates(1).first?.string else { return nil }
      let box = observation.boundingBox
      return GridLabel(
        text: text,
        bounds: CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height))
    }
  }
}
