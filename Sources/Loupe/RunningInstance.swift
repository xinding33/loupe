import AppKit
import LoupeCore

extension ProcessStart {
  /// When the process with this pid started, or nil when the kernel won't say, as once it has
  /// exited.
  static func of(_ pid: pid_t) -> ProcessStart? {
    guard pid > 0 else { return nil }
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    return ProcessStart(seconds: info.pbi_start_tvsec, microseconds: info.pbi_start_tvusec)
  }
}

extension AutoPressTarget {
  /// A running app as a target. Nil when it has no bundle identifier and its start time can't be
  /// read, since that target could never match.
  init?(running app: NSRunningApplication) {
    let pid = app.processIdentifier
    self.init(
      bundleID: app.bundleIdentifier, pid: pid, start: { ProcessStart.of(pid) },
      name: app.localizedName ?? app.executableURL?.lastPathComponent ?? "Unnamed app")
  }

  /// Whether `app` is the target. Fails closed when there's no app.
  func matches(_ app: NSRunningApplication?) -> Bool {
    guard let app else { return false }
    let pid = app.processIdentifier
    return matches(bundleID: app.bundleIdentifier, pid: pid) { ProcessStart.of(pid) }
  }

  /// Whether an instance target is still running. Always true for an app.
  var isRunning: Bool {
    guard isInstance else { return true }
    guard let pid, let start else { return false }
    return ProcessStart.of(pid) == start
  }
}
