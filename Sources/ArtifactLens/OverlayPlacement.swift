import AppKit
import SwiftUI

struct OverlayDisplay: Equatable {
  let id: CGDirectDisplayID
  let frame: CGRect
  let safeFrame: CGRect
  let scale: CGFloat
}

struct OverlayPlacement: Equatable {
  let windowFrame: CGRect
  let display: OverlayDisplay
  let panelFrame: CGRect

  static func resolve(
    window: CGRect, displays: [OverlayDisplay], size: CGSize, offset: CGPoint
  ) -> OverlayPlacement? {
    guard !window.isEmpty, !window.isInfinite, !window.isNull,
      let display = displays.max(by: {
        area(window.intersection($0.frame)) < area(window.intersection($1.frame))
      }), area(window.intersection(display.frame)) > 0,
      display.safeFrame.width > 0, display.safeFrame.height > 0
    else { return nil }
    let safe = display.safeFrame
    let width = min(size.width, safe.width)
    let height = min(size.height, safe.height)
    let x = min(safe.maxX - width, max(safe.minX, safe.maxX - width - 12 + offset.x))
    let y = min(safe.maxY - height, max(safe.minY, safe.maxY - height - 12 + offset.y))
    return OverlayPlacement(
      windowFrame: window, display: display,
      panelFrame: CGRect(x: x, y: y, width: width, height: height))
  }

  static func appKitFrame(_ quartz: CGRect, primaryTop: CGFloat) -> CGRect {
    CGRect(x: quartz.minX, y: primaryTop - quartz.maxY, width: quartz.width, height: quartz.height)
  }

  private static func area(_ rect: CGRect) -> CGFloat {
    rect.isNull || rect.isEmpty ? 0 : rect.width * rect.height
  }
}

@MainActor
private final class OverlayPanel: NSPanel {
  override var canBecomeKey: Bool { false }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
  private let model: Model
  private let panel: NSPanel
  private let controls: NSPanel
  private var timer: Timer?
  private let defaults: UserDefaults
  private var offset: CGPoint
  private var dragOrigin: CGPoint?
  private(set) var placement: OverlayPlacement?

  init(model: Model, defaults: UserDefaults = .standard) {
    self.model = model
    self.defaults = defaults
    offset = CGPoint(
      x: defaults.double(forKey: "overlayOffsetX"), y: defaults.double(forKey: "overlayOffsetY"))
    if !offset.x.isFinite || !offset.y.isFinite { offset = .zero }
    panel = Self.makePanel()
    controls = Self.makePanel()
    panel.ignoresMouseEvents = true
    panel.contentView = NSHostingView(rootView: OverlayView(model: model))
    controls.contentView = NSHostingView(
      rootView: OverlayControls(
        model: model,
        drag: { [weak self] delta, finished in self?.drag(delta, finished: finished) }))
    model.updateOverlay = { [weak self] in self?.update() }
    model.resetOverlayPlacement = { [weak self] in self?.resetPlacement() }
    update()
  }

  private static func makePanel() -> NSPanel {
    let panel = OverlayPanel(
      contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false)
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isMovable = false
    return panel
  }

  func update() {
    if !model.enabled {
      timer?.invalidate()
      timer = nil
      panel.orderOut(nil)
      controls.orderOut(nil)
      placement = nil
      model.diagnosticPlacement = nil
      return
    }
    if timer == nil {
      timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.refreshPlacement() }
      }
    }
    refreshPlacement()
  }

  private func refreshPlacement() {
    guard model.enabled else { return }
    let screens = NSScreen.screens
    guard let id = model.capture.selectedWindowID,
      let primary = screens.first,
      let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]],
      let bounds = info.first?[kCGWindowBounds as String] as? [String: Any],
      let quartz = CGRect(dictionaryRepresentation: bounds as CFDictionary)
    else {
      placement = nil
      model.diagnosticPlacement = nil
      panel.orderOut(nil)
      controls.orderOut(nil)
      model.placementStatus =
        "Shared window unavailable. Choose game window again to recover placement."
      return
    }
    let displays = screens.compactMap { screen -> OverlayDisplay? in
      guard
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      else { return nil }
      return OverlayDisplay(
        id: number.uint32Value, frame: screen.frame, safeFrame: screen.visibleFrame,
        scale: screen.backingScaleFactor)
    }
    let size = CGSize(
      width: model.overlayExpanded ? 360 : 280, height: model.overlayExpanded ? 630 : 140)
    guard
      let next = OverlayPlacement.resolve(
        window: OverlayPlacement.appKitFrame(quartz, primaryTop: primary.frame.maxY),
        displays: displays, size: size, offset: offset)
    else {
      placement = nil
      model.diagnosticPlacement = nil
      panel.orderOut(nil)
      controls.orderOut(nil)
      model.placementStatus =
        "Shared window is outside available displays. Move it, then reset placement."
      return
    }
    placement = next
    let previousGeometry = model.diagnosticPlacement
    model.diagnosticPlacement = DiagnosticPlacement(
      window: next.windowFrame, displays: displays.map(\.frame),
      selectedDisplay: displays.firstIndex(where: { $0.id == next.display.id }),
      overlay: next.panelFrame, scale: next.display.scale)
    if previousGeometry != model.diagnosticPlacement {
      model.recordDiagnosticDisplay()
    }
    let frame = next.panelFrame
    let handleHeight = min(28.0, frame.height)
    controls.setFrame(
      CGRect(x: frame.minX, y: frame.maxY - handleHeight, width: frame.width, height: handleHeight),
      display: true)
    panel.setFrame(
      CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height - handleHeight),
      display: true)
    panel.orderFrontRegardless()
    controls.orderFrontRegardless()
    model.placementStatus =
      "Anchored to the shared window's display. Drag the grip to adjust; Reset restores the corner."
  }

  private func drag(_ delta: CGSize, finished: Bool) {
    if dragOrigin == nil { dragOrigin = offset }
    if let dragOrigin {
      offset = CGPoint(x: dragOrigin.x + delta.width, y: dragOrigin.y - delta.height)
    }
    refreshPlacement()
    if finished {
      dragOrigin = nil
      saveOffset()
    }
  }

  private func resetPlacement() {
    offset = .zero
    dragOrigin = nil
    saveOffset()
    refreshPlacement()
  }

  private func saveOffset() {
    defaults.set(offset.x, forKey: "overlayOffsetX")
    defaults.set(offset.y, forKey: "overlayOffsetY")
  }
}

private struct OverlayControls: View {
  @ObservedObject var model: Model
  let drag: (CGSize, Bool) -> Void

  var body: some View {
    HStack(spacing: 2) {
      Image(systemName: "line.3.horizontal")
        .foregroundStyle(.secondary)
        .frame(width: 22, height: 22)
        .help("Drag to move the overlay")
        .accessibilityLabel("Move overlay; Reset placement is also available in the main window")
      Text("Artifact Lens").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
        .lineLimit(1).allowsHitTesting(false)
      Spacer(minLength: 4)
      icon(
        model.overlayExpanded ? "chevron.up" : "chevron.down",
        help: model.overlayExpanded ? "Collapse" : "Expand"
      ) { model.overlayExpanded.toggle() }
      icon("arrow.uturn.backward", help: "Reset placement") { model.resetOverlayPlacement?() }
      Button {
        model.reportIssue()
      } label: {
        Label("Report", systemImage: "exclamationmark.bubble").font(.system(size: 10.5))
          .padding(.horizontal, 6).frame(height: 20)
          .background(Theme.surfaceStrong, in: Capsule())
      }
      .help("Report issue").accessibilityLabel("Report issue")
      icon("power", help: "Disable reader") { model.setEnabled(false) }
    }
    .buttonStyle(.plain).padding(.leading, 4).padding(.trailing, 6)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .gesture(
      DragGesture().onChanged { drag($0.translation, false) }.onEnded { drag($0.translation, true) }
    )
    .background(
      Theme.hud.opacity(0.97),
      in: UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12, style: .continuous)
    )
    .preferredColorScheme(.dark)
  }

  private func icon(_ name: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: name).font(.system(size: 11, weight: .semibold))
        .frame(width: 22, height: 22).contentShape(Rectangle())
    }
    .help(help).accessibilityLabel(help)
  }
}
