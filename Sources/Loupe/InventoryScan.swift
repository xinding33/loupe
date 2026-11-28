import AppKit
import LoupeCore
import Vision

/// What the last inventory scan did, for the summary and review list under Saved inventory.
struct ScanReport: Equatable {
  let merge: SweepMerge
  let ending: InventorySweep.Ending?
  /// Tiles whose card couldn't be read.
  let missed: Int
  /// One- to three-star pieces, which Loupe doesn't save.
  let passed: Int
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
    if let ending { text += " " + Self.describe(ending) }
    return text
  }

  static func describe(_ ending: InventorySweep.Ending) -> String {
    switch ending {
    case .belowMinimum: "Stopped at the first +0 piece."
    case .endOfList: "Reached the end of the list."
    case .clicksNotLanding:
      "Stopped: clicked tiles kept showing the same card, so clicks aren't reaching the game."
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
/// from the user, when the game leaves the front, or when the reader stops.
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
  /// Cards read while scanning, in order, with when their frames arrived.
  private var readings: [(frame: TimeInterval, card: InventorySweep.Card?)] = []
  /// Where and when Loupe last moved the pointer, to tell its own move from the user's.
  private var lastPosted: (point: CGPoint, time: TimeInterval)?
  private let source = CGEventSource(stateID: .hidSystemState)

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
      model.cardObserver = nil
      state = .idle
      task = nil
    }
    guard await waitForGame(target) else {
      progress = interruption ?? "The game didn't come to the front, so the scan didn't start."
      return
    }
    state = .running
    readings = []
    // The scan belongs to one capture session: a new stream, even of the same window, ends it.
    guard let session = model.capture.sessionID, model.capture.selectedWindowID == windowID else {
      progress = "The shared window changed, so the scan didn't start."
      return
    }
    self.session = session
    model.cardObserver = { [weak self] card, frame in
      guard let self, model.capture.sessionID == session else { return }
      let now = ProcessInfo.processInfo.systemUptime
      readings.removeAll { now - $0.frame > 10 }
      readings.append((frame, card))
    }
    installMonitor()
    model.beginScan()
    model.banner?("Scanning Inventory. Move the mouse to stop.")
    progress = "Scanning. Move the mouse or press a key to stop."
    let context = ScanContext(windowID: windowID, target: target)
    guard let first = await firstScreen() else {
      model.finishScan(nil)
      report(
        "Couldn't find the Inventory grid. Open Inventory with an artifact selected, then scan.")
      return
    }
    // Every levelled piece: the list is sorted by level, so the first +0 ends it.
    var sweep = InventorySweep(minimumLevel: 1, screen: first.grid)
    var known = first.grid
    var view = first.view
    var before = first.picture
    var step = sweep.start()
    var failure: String?
    loop: while true {
      let sharing =
        model.enabled && model.capture.isCapturing && model.capture.sessionID == session
      if Task.isCancelled || !sharing {
        if !sharing { interruption = interruption ?? "The reader stopped sharing the game window." }
        step = sweep.stop()
      }
      do {
        switch step {
        case .finish:
          break loop
        case .click(_, let point, let level):
          let pressed = try await click(point, context)
          var card = await card(after: pressed, level: level)
          // The card on screen before the press, from frames taken then, however late read.
          let shown = readings.last { $0.frame < pressed && $0.card?.key != nil }?.card
          if let key = card.key, key == shown?.key { card = .unchanged }
          // Readings from another capture session say nothing about this tile.
          if model.capture.sessionID != session { card = .unread }
          step = sweep.clicked(card)
          progress =
            "Scanning: \(sweep.pieces.count + sweep.others.count) read. Move the mouse to stop."
        case .scroll(let lines, let expected):
          try await scroll(lines, at: view.center, context)
          guard
            var next = await settledScreen(known: known, view: view, cardLeft: first.cardLeft)
          else {
            step = sweep.scrolled(to: nil, moved: nil)
            continue
          }
          var moved = view.shift(from: before, to: next.picture, expected: expected)
          // Generously, since the sweep refines this estimate before judging it.
          if let small = moved, abs(small) < 0.3 * view.rowPitch {
            // A streamed game can take a moment to answer the wheel. Look again before taking
            // the list for still, which can end the scan; without a second look, don't.
            try? await Task.sleep(for: .seconds(1))
            if let again = await settledScreen(known: known, view: view, cardLeft: first.cardLeft) {
              next = again
              moved = view.shift(from: before, to: again.picture, expected: expected)
            } else {
              moved = nil
            }
          }
          step = sweep.scrolled(to: next.grid, moved: moved)
          if let grid = next.grid {
            known = grid
            view = view.with(grid)
          }
          before = next.picture
        }
      } catch {
        failure = error.localizedDescription
        step = sweep.stop()
      }
    }
    model.finishScan(sweep)
    let summary = model.lastScan?.summary ?? ""
    if let reason = failure ?? interruption, sweep.ending == .stopped {
      progress = reason + " " + summary
      model.banner?("Scan stopped")
    } else {
      progress = summary
      model.banner?("Scan finished: \(sweep.pieces.count) read")
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

  /// Waits for the card the tile shows: the two newest readings, both of frames that arrived
  /// after the click had time to show, agreeing. A card that disagrees with the level read under
  /// the tile is taken only after a second and a half, in case the label was misread. A card
  /// that's still the last tile's is returned too; the sweep clicks again and then gives up.
  private func card(after click: TimeInterval, level: Int?) async -> InventorySweep.Card {
    // The game, and a stream from GeForce NOW, take a moment to show the new card.
    let fresh = click + 0.3
    while !Task.isCancelled {
      let now = ProcessInfo.processInfo.systemUptime
      let recent = readings.filter { $0.frame >= fresh }.suffix(2).map(\.card)
      if recent.count == 2, let card = recent[1], let signature = card.signature,
        recent[0]?.signature == signature
      {
        if level == nil || card.level == level || now >= click + 1.5 { return card }
      }
      if now >= click + 4 { return .unread }
      try? await Task.sleep(for: .milliseconds(50))
    }
    return .unread
  }

  // MARK: Reading the grid

  private struct Screen {
    let grid: InventoryGrid?
    let picture: GrayImage
  }

  /// The first screen: where the card starts, so labels right of it aren't taken as tiles.
  private func firstScreen() async -> (
    grid: InventoryGrid, view: ScanView, picture: GrayImage, cardLeft: Double
  )? {
    guard let image = await model.capture.nextFrame(),
      let left = await Task.detached(operation: { GridReader.cardLeft(in: image) }).value,
      let second = await model.capture.nextFrame()
    else { return nil }
    let labels = await Task.detached {
      GridReader.labels(in: image, left: left) + GridReader.labels(in: second, left: left)
    }.value
    guard let found = InventoryGrid.detect(labels), found.rows.count >= 2,
      let view = ScanView(found), let picture = view.picture(of: second)
    else { return nil }
    let grid = GridReader.markVacant(found, in: second)
    return (grid, view, picture, left)
  }

  /// The screen once a scroll has stopped moving: two frames in a row with nothing moved.
  private func settledScreen(known: InventoryGrid, view: ScanView, cardLeft: Double) async
    -> Screen?
  {
    try? await Task.sleep(for: .milliseconds(300))
    guard var image = await model.capture.nextFrame(), var picture = view.picture(of: image)
    else { return nil }
    let deadline = ProcessInfo.processInfo.systemUptime + 3
    while ProcessInfo.processInfo.systemUptime < deadline {
      guard let next = await model.capture.nextFrame(), let nextPicture = view.picture(of: next)
      else { return nil }
      if GrayImage.verticalShift(from: picture, to: nextPicture, within: -4...4) == 0 {
        let earlier = image
        let labels = await Task.detached {
          GridReader.labels(in: earlier, left: cardLeft)
            + GridReader.labels(in: next, left: cardLeft)
        }.value
        return Screen(
          grid: InventoryGrid.detect(labels, known: known).map {
            GridReader.markVacant($0, in: next)
          }, picture: nextPicture)
      }
      image = next
      picture = nextPicture
    }
    return nil
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

  /// Turns the wheel over the grid, a line at a time.
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

/// The part of the window the grid scrolls in, as a small grayscale picture for measuring
/// scrolls, and where to point the wheel.
struct ScanView {
  /// Window coordinates from the top left.
  let area: CGRect
  let rowPitch: Double
  static let size = (width: 120, height: 240)

  init?(_ grid: InventoryGrid) {
    guard let first = grid.columns.first, let last = grid.columns.last,
      let top = grid.rows.first?.y, let bottom = grid.rows.last?.y
    else { return nil }
    let x = first - 0.5 * grid.columnPitch
    let y = top - 0.6 * grid.rowPitch
    area = CGRect(
      x: x, y: y, width: last + 0.5 * grid.columnPitch - x, height: bottom + 0.03 - y)
    rowPitch = grid.rowPitch
    guard area.width > 0, area.height > 0 else { return nil }
  }

  private init(area: CGRect, rowPitch: Double) {
    self.area = area
    self.rowPitch = rowPitch
  }

  /// The same area with a newer row pitch.
  func with(_ grid: InventoryGrid) -> ScanView { ScanView(area: area, rowPitch: grid.rowPitch) }

  var center: CGPoint { CGPoint(x: area.midX, y: area.midY) }

  func picture(of image: CGImage) -> GrayImage? {
    let rect = CGRect(
      x: area.minX * Double(image.width), y: area.minY * Double(image.height),
      width: area.width * Double(image.width), height: area.height * Double(image.height)
    ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard !rect.isEmpty, let crop = image.cropping(to: rect) else { return nil }
    let (width, height) = Self.size
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

  /// How far the content moved up between two pictures, in window heights. With an expected
  /// move, the search runs from no move to a little past it, since a list that ends early moves
  /// less. Nil when no move in range fits, or when the pictures differ but line up best unmoved,
  /// as they can after a jump of whole rows.
  func shift(from before: GrayImage, to after: GrayImage, expected: Double?) -> Double? {
    // Only the selected tile's pulsing highlight changes on a still screen.
    if let difference = GrayImage.meanDifference(before, after), difference < 4 { return 0 }
    let scale = Double(Self.size.height) / area.height
    let limit = Int(Double(Self.size.height) * 0.8)
    let range: ClosedRange<Int>
    if let expected {
      let margin = 0.45 * rowPitch * scale
      let low = max(-limit, Int((min(0, expected * scale) - margin).rounded(.down)))
      let high = min(limit, Int((max(0, expected * scale) + margin).rounded(.up)))
      guard low <= high else { return nil }
      range = low...high
    } else {
      range = -limit...limit
    }
    guard let pixels = GrayImage.verticalShift(from: before, to: after, within: range),
      pixels != 0
    else { return nil }
    return Double(pixels) / scale
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

  /// Marks the tiles with no level label and none of the pale strip the label sits on, about
  /// three quarters of a tile's strip and none of the background behind the grid.
  static func markVacant(_ grid: InventoryGrid, in image: CGImage) -> InventoryGrid {
    var grid = grid
    for row in grid.rows.indices {
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
