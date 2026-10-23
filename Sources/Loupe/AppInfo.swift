import Foundation
import LoupeCore
import os

let appName = "Loupe"
let bundleID = Bundle.main.bundleIdentifier ?? "io.github.xinding33.loupe"
let appVersion =
  Version(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
  ?? Version("0.0.0")!
/// Read it with: /usr/bin/log stream --predicate 'subsystem == "io.github.xinding33.loupe"' --level info
/// (zsh has its own `log` builtin, hence the full path.)
let log = Logger(subsystem: bundleID, category: "app")
