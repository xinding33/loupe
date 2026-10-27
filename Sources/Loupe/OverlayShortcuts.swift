import Carbon
import Foundation
import LoupeCore

struct OverlayShortcut: Equatable {
  let keyCode: UInt32
  let modifiers: UInt32

  init(_ text: String) throws {
    let parts = text.lowercased().split(separator: "+", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
    let keys: [String: UInt32] = [
      "`": 50, "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
      "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13,
      "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
      "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
      "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35,
      "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
    let flags: [String: UInt32] = [
      "option": UInt32(optionKey), "shift": UInt32(shiftKey),
      "control": UInt32(controlKey), "command": UInt32(cmdKey),
    ]
    guard parts.count >= 2, let last = parts.last, let key = keys[last] else {
      throw ArtifactError("Use modifiers + a letter, digit, or backtick, such as option+`.")
    }
    var mask: UInt32 = 0
    for part in parts.dropLast() {
      guard let flag = flags[part], mask & flag == 0 else {
        throw ArtifactError("Use each modifier once: option, shift, control, or command.")
      }
      mask |= flag
    }
    guard mask & UInt32(optionKey | controlKey | cmdKey) != 0 else {
      throw ArtifactError("Include option, control, or command in each shortcut.")
    }
    keyCode = key
    modifiers = mask
  }
}

@MainActor
protocol ShortcutBackend: AnyObject {
  var event: ((UInt32, Bool) -> Void)? { get set }
  func register(_ shortcut: OverlayShortcut, id: UInt32) throws
  func unregisterAll()
}

@MainActor
final class OverlayShortcuts {
  private let backend: any ShortcutBackend
  private var held: Set<UInt32> = []
  var expand: (() -> Void)?
  var toggleEnabled: (() -> Void)?
  var snapshot: (() -> Void)?
  var toggleRecording: (() -> Void)?

  init(backend: any ShortcutBackend) {
    self.backend = backend
    backend.event = { [weak self] id, pressed in
      guard let self else { return }
      if !pressed {
        held.remove(id)
        return
      }
      guard held.insert(id).inserted else { return }
      switch id {
      case 1: expand?()
      case 2: toggleEnabled?()
      case 3: snapshot?()
      case 4: toggleRecording?()
      default: break
      }
    }
  }

  func configure(expand: String, enable: String, snapshot: String, record: String) throws {
    let shortcuts = try [expand, enable, snapshot, record].map(OverlayShortcut.init)
    guard Set(shortcuts.map { [$0.keyCode, $0.modifiers] }).count == shortcuts.count else {
      throw ArtifactError("Choose a different shortcut for each action.")
    }
    backend.unregisterAll()
    held.removeAll()
    do {
      for (index, shortcut) in shortcuts.enumerated() {
        try backend.register(shortcut, id: UInt32(index + 1))
      }
    } catch {
      backend.unregisterAll()
      throw ArtifactError(
        "Shortcuts are unavailable. Use the main-window controls. \(error.localizedDescription)")
    }
  }
}

@MainActor
final class CarbonShortcutBackend: ShortcutBackend {
  /// 'ALEN'.
  static let signature: OSType = 0x414C_454E
  var event: ((UInt32, Bool) -> Void)?
  private var handler: EventHandlerRef?
  private var registrations: [EventHotKeyRef] = []

  func register(_ shortcut: OverlayShortcut, id: UInt32) throws {
    if handler == nil {
      var types = [
        EventTypeSpec(
          eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
        EventTypeSpec(
          eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
      ]
      let status = InstallEventHandler(
        GetApplicationEventTarget(),
        { _, event, context in
          guard let event, let context else { return OSStatus(eventNotHandledErr) }
          var id = EventHotKeyID()
          let status = GetEventParameter(
            event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
            nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
          guard status == noErr else { return status }
          // Auto-press registers its toggle on the same event target with its own signature.
          guard id.signature == CarbonShortcutBackend.signature else {
            return OSStatus(eventNotHandledErr)
          }
          let backend = Unmanaged<CarbonShortcutBackend>.fromOpaque(context).takeUnretainedValue()
          let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
          MainActor.assumeIsolated { backend.event?(id.id, pressed) }
          return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
      guard status == noErr else {
        throw ArtifactError("Cannot install shortcut listener (\(status)).")
      }
    }
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      shortcut.keyCode, shortcut.modifiers,
      EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(),
      OptionBits(kEventHotKeyExclusive), &reference)
    guard status == noErr, let reference else {
      throw ArtifactError("Shortcut registration failed or conflicts with another app (\(status)).")
    }
    registrations.append(reference)
  }

  func unregisterAll() {
    for reference in registrations { UnregisterEventHotKey(reference) }
    registrations.removeAll()
  }

  func close() {
    unregisterAll()
    if let handler { RemoveEventHandler(handler) }
    handler = nil
  }
}
