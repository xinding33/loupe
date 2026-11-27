import AppKit
import Carbon.HIToolbox
import LoupeCore
import SwiftUI
import UniformTypeIdentifiers

struct AutoPressPanel: View {
  @ObservedObject var autoPress: AutoPress

  var body: some View {
    Panel(title: "Auto-press", systemImage: "keyboard") {
      Toggle(
        "Press \(autoPress.keyName) repeatedly",
        isOn: Binding(get: { autoPress.session.isOn }, set: { autoPress.setOn($0) })
      )
      .toggleStyle(.switch)
      TimelineView(.periodic(from: .now, by: 15)) { context in
        Text(autoPress.status(at: context.date)).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if !autoPress.accessibilityGranted {
        Text("Needs Accessibility access to press keys.")
          .font(.caption).foregroundStyle(Theme.attention)
        Button("Open Accessibility settings", systemImage: "lock.shield") {
          autoPress.openAccessibilitySettings()
        }
      }
      Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
        GridRow {
          Text("Key").font(.caption)
          KeyRecorder(title: autoPress.keyName, keysOnly: true) { candidate in
            guard case .key(let keyCode, _) = candidate else { return nil }
            if let rejection = autoPress.rejection(forPressedKey: keyCode) { return rejection }
            autoPress.settings.pressedKeyCode = keyCode
            return nil
          }
        }
        GridRow {
          Text("Toggle").font(.caption)
          KeyRecorder(title: autoPress.settings.trigger.displayName) { candidate in
            if let rejection = autoPress.rejection(forTrigger: candidate) { return rejection }
            autoPress.settings.trigger = candidate
            return nil
          }
        }
        GridRow {
          Text("In app").font(.caption)
          HStack(spacing: 6) {
            Text(autoPress.settings.target.name).font(.caption).lineLimit(1)
              .truncationMode(.middle)
            TargetChooser(
              current: autoPress.settings.target,
              choose: { autoPress.settings.target = $0 }, chooseOther: chooseApplication
            )
            .fixedSize()
          }
        }
      }
      if autoPress.settings.target.isInstance {
        // Notices the instance quitting on the status line's refresh.
        TimelineView(.periodic(from: .now, by: 15)) { _ in
          Text(autoPress.instanceNote ?? "").font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Stepper(
        "\(autoPress.settings.pressesPerSecond) presses per second",
        value: $autoPress.settings.pressesPerSecond, in: AutoPressSettings.pressesPerSecondRange
      )
      .font(.caption)
      HStack(spacing: 6) {
        Toggle("Off after", isOn: $autoPress.settings.autoOffEnabled).font(.caption)
        TextField("Minutes", value: $autoPress.settings.autoOffMinutes, format: .number)
          .labelsHidden().multilineTextAlignment(.trailing).frame(width: 44)
          .textFieldStyle(.roundedBorder).font(.caption)
          .disabled(!autoPress.settings.autoOffEnabled)
        Text("min").font(.caption)
      }
      .toggleStyle(.switch)
      if let issue = autoPress.triggerIssue {
        Text(issue).font(.caption).foregroundStyle(Theme.attention)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(
        "Presses only while \(autoPress.settings.target.name) is in front. The toggle works only there, so other apps keep that key. A banner confirms on and off."
      )
      .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    .controlSize(.small)
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      autoPress.refreshAccessibility()
    }
  }

  private func chooseApplication() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.application]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
      let bundleID = bundle.bundleIdentifier
    else { return }
    let name =
      bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? url.deletingPathExtension().lastPathComponent
    autoPress.settings.target = AutoPressTarget(bundleID: bundleID, name: name)
  }
}

/// A "Choose…" pull-down: GeForce NOW, which is always there to go back to, the apps running now
/// and a picker for one that isn't. The list is built each time it opens, so a game started
/// after Loupe is in it. A process with no app bundle, such as a game under Wine, can be picked
/// only from the running apps, and then only for that run.
private struct TargetChooser: NSViewRepresentable {
  let current: AutoPressTarget
  let choose: (AutoPressTarget) -> Void
  let chooseOther: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: true)
    // A pull-down's first item is its title.
    button.addItem(withTitle: "Choose…")
    button.menu?.delegate = context.coordinator
    updateNSView(button, context: context)
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.chooser = self
    let size = NSControl.ControlSize(context.environment.controlSize)
    guard button.controlSize != size else { return }
    button.controlSize = size
    button.font = .systemFont(ofSize: NSFont.systemFontSize(for: size))
  }

  @MainActor
  final class Coordinator: NSObject, NSMenuDelegate {
    var chooser: TargetChooser
    private var targets: [AutoPressTarget] = []

    init(_ chooser: TargetChooser) { self.chooser = chooser }

    func menuNeedsUpdate(_ menu: NSMenu) {
      let current = chooser.current
      let own = NSRunningApplication.current.processIdentifier
      // An app object can outlive its process, whose pid may by then belong to another.
      let running = NSWorkspace.shared.runningApplications
        .filter {
          $0.activationPolicy == .regular && $0.processIdentifier != own && !$0.isTerminated
        }
        .compactMap(AutoPressTarget.init(running:))
      // A picked game that has quit can't be chosen again, so it isn't offered. The panel's note
      // says it has quit.
      targets = AutoPressTarget.choices(current: current, running: running)
        .filter(\.isRunning)
      let titles = AutoPressTarget.titles(targets)
      while menu.items.count > 1 { menu.removeItem(at: menu.items.count - 1) }
      for (index, target) in targets.enumerated() {
        let item = NSMenuItem(title: titles[index], action: #selector(pick), keyEquivalent: "")
        item.target = self
        item.tag = index
        item.state = target.sameIdentity(as: current) ? .on : .off
        menu.addItem(item)
        if index == 0, targets.count > 1 { menu.addItem(.separator()) }
      }
      menu.addItem(.separator())
      let other = NSMenuItem(title: "Other App…", action: #selector(other), keyEquivalent: "")
      other.target = self
      menu.addItem(other)
    }

    @objc private func pick(_ item: NSMenuItem) {
      guard targets.indices.contains(item.tag) else { return }
      chooser.choose(targets[item.tag])
    }

    @objc private func other() { chooser.chooseOther() }
  }
}

extension NSControl.ControlSize {
  fileprivate init(_ size: SwiftUI.ControlSize) {
    switch size {
    case .mini: self = .mini
    case .small: self = .small
    case .large: self = .large
    default: self = .regular
    }
  }
}

/// Records the next key, key combination or extra mouse button pressed in this window.
private struct KeyRecorder: View {
  let title: String
  /// Limits recording to a single key, ignoring modifiers and mouse buttons.
  var keysOnly = false
  /// Stores the candidate, or returns why it can't be used.
  let record: (AutoPressTrigger) -> String?

  @State private var monitor: Any?
  @State private var rejection: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Button {
        if monitor == nil { startRecording() } else { stopRecording() }
      } label: {
        Text(monitor == nil ? title : keysOnly ? "Press key…" : "Press shortcut…")
          .frame(minWidth: 70)
      }
      .help(
        keysOnly
          ? "Click, then press the key to repeat. Esc cancels."
          : "Click, then press a key, a key combination or an extra mouse button. Esc cancels.")
      if let rejection {
        Text(rejection).font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .onDisappear(perform: stopRecording)
  }

  private func startRecording() {
    rejection = nil
    monitor = NSEvent.addLocalMonitorForEvents(
      matching: keysOnly ? .keyDown : [.keyDown, .otherMouseDown]
    ) { event in
      if event.type == .otherMouseDown {
        finish(.mouse(button: event.buttonNumber))
      } else if event.keyCode == UInt16(kVK_Escape) {
        stopRecording()
      } else {
        let modifiers = keysOnly ? [] : KeyModifiers(event.modifierFlags)
        finish(.key(keyCode: event.keyCode, modifiers: modifiers))
      }
      return nil
    }
  }

  private func finish(_ candidate: AutoPressTrigger) {
    rejection = record(candidate)
    if rejection == nil { stopRecording() }
  }

  private func stopRecording() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
  }
}
