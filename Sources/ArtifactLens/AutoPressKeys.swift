import AppKit
import ArtifactCore
import Carbon.HIToolbox

extension KeyModifiers {
  init(_ flags: NSEvent.ModifierFlags) {
    self = []
    if flags.contains(.command) { insert(.command) }
    if flags.contains(.option) { insert(.option) }
    if flags.contains(.control) { insert(.control) }
    if flags.contains(.shift) { insert(.shift) }
  }

  var carbon: UInt32 {
    var result = 0
    if contains(.command) { result |= cmdKey }
    if contains(.option) { result |= optionKey }
    if contains(.control) { result |= controlKey }
    if contains(.shift) { result |= shiftKey }
    return UInt32(result)
  }

  var symbols: String {
    var result = ""
    if contains(.control) { result += "⌃" }
    if contains(.option) { result += "⌥" }
    if contains(.shift) { result += "⇧" }
    if contains(.command) { result += "⌘" }
    return result
  }
}

extension AutoPressTrigger {
  var displayName: String {
    switch self {
    case .key(let keyCode, let modifiers):
      return modifiers.symbols + autoPressKeyName(keyCode)
    case .mouse(let button):
      return button == 2 ? "Middle mouse button" : "Mouse button \(button + 1)"
    }
  }

  /// Whether this trigger is the same key combination as one of the overlay's shortcuts.
  func matches(_ shortcut: OverlayShortcut) -> Bool {
    guard case .key(let keyCode, let modifiers) = self else { return false }
    return UInt32(keyCode) == shortcut.keyCode && modifiers.carbon == shortcut.modifiers
  }
}

private let specialKeyNames: [Int: String] = [
  kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
  kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
  kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
  kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
  kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
  kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17",
  kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
]

/// The key's label on the current keyboard layout, such as "F" or "`".
func autoPressKeyName(_ keyCode: UInt16) -> String {
  if let name = specialKeyNames[Int(keyCode)] { return name }
  let fallback = "Key \(keyCode)"

  guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
    let layoutPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
  else { return fallback }
  let layoutData = unsafeBitCast(layoutPointer, to: CFData.self) as Data

  var deadKeyState: UInt32 = 0
  var chars = [UniChar](repeating: 0, count: 4)
  var length = 0
  let status = layoutData.withUnsafeBytes { bytes in
    UCKeyTranslate(
      bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress, keyCode,
      UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
      OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState, chars.count, &length, &chars)
  }
  guard status == noErr, length > 0 else { return fallback }
  return String(utf16CodeUnits: chars, count: length).uppercased()
}
