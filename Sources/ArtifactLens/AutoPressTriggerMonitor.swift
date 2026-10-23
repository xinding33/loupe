import AppKit
import ArtifactCore
import Carbon.HIToolbox

/// Listens for the auto-press toggle. Key triggers use a Carbon hot key; mouse triggers use an
/// event tap, which needs Accessibility access. Both swallow the trigger so the game never sees it.
@MainActor
final class AutoPressTriggerMonitor {
  /// 'MASH'. The overlay's shortcuts use another signature on the same event target.
  static let signature: OSType = 0x4D41_5348

  var onTrigger: (() -> Void)?
  /// Why the trigger could not be installed, if it couldn't. A failed install is retried on the
  /// next update.
  private(set) var issue: String?

  private var installed: AutoPressTrigger?
  private var failed: AutoPressTrigger?
  private var hotKeyRef: EventHotKeyRef?
  private var eventTap: CFMachPort?
  private var eventTapSource: CFRunLoopSource?
  private var mouseButton: Int64 = -1

  init() {
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        let status = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
          nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard status == noErr, id.signature == AutoPressTriggerMonitor.signature else {
          return OSStatus(eventNotHandledErr)
        }
        let monitor = Unmanaged<AutoPressTriggerMonitor>.fromOpaque(userData)
          .takeUnretainedValue()
        MainActor.assumeIsolated { monitor.onTrigger?() }
        return noErr
      }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), nil)
  }

  /// Installs `trigger` while `active`, and removes it otherwise. A failed install is retried on
  /// the next call. Its issue stays visible after the target app goes to the background, because
  /// that is when the main window can be seen.
  func update(trigger: AutoPressTrigger, active: Bool) {
    if trigger != failed {
      failed = nil
      issue = nil
    }
    let wanted = active ? trigger : nil
    guard wanted != installed else { return }

    uninstall()
    guard let wanted else { return }

    switch wanted {
    case .key(let keyCode, let modifiers):
      let status = RegisterEventHotKey(
        UInt32(keyCode), modifiers.carbon, EventHotKeyID(signature: Self.signature, id: 1),
        GetApplicationEventTarget(), 0, &hotKeyRef)
      if status != noErr {
        hotKeyRef = nil
        issue = "\(wanted.displayName) is taken by another shortcut (\(status)). Choose another."
      }
    case .mouse(let button):
      if !installMouseTap(button: button) {
        issue = "A mouse-button toggle needs Accessibility access."
      }
    }
    if issue == nil {
      installed = wanted
    } else {
      failed = wanted
    }
  }

  private func installMouseTap(button: Int) -> Bool {
    let mask = CGEventMask(
      1 << CGEventType.otherMouseDown.rawValue | 1 << CGEventType.otherMouseUp.rawValue)
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask,
        callback: { _, type, event, userInfo in
          guard let userInfo else { return Unmanaged.passUnretained(event) }
          let monitor = Unmanaged<AutoPressTriggerMonitor>.fromOpaque(userInfo)
            .takeUnretainedValue()
          let button = event.getIntegerValueField(.mouseEventButtonNumber)
          let swallow = MainActor.assumeIsolated {
            monitor.handleMouseEvent(type: type, button: button)
          }
          return swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }

    mouseButton = Int64(button)
    eventTap = tap
    eventTapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    return true
  }

  /// Whether to swallow the event.
  private func handleMouseEvent(type: CGEventType, button: Int64) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
      return false
    }
    guard button == mouseButton else { return false }
    if type == .otherMouseDown { onTrigger?() }
    return true
  }

  private func uninstall() {
    installed = nil
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
    }
    if let eventTap {
      CGEvent.tapEnable(tap: eventTap, enable: false)
      CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes)
      CFMachPortInvalidate(eventTap)
      self.eventTap = nil
      eventTapSource = nil
    }
  }
}
