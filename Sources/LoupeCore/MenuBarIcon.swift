/// What the menu bar icon shows: the reader's state, and whether auto-press is pressing keys.
public struct MenuBarIcon: Equatable, Sendable {
  /// An SF Symbol name.
  public let symbol: String
  /// Drawn dimmed, the way the menu bar shows something that's off.
  public let dimmed: Bool
  public let toolTip: String

  public init(readerEnabled: Bool, autoPressOn: Bool) {
    symbol = autoPressOn ? "dot.viewfinder" : "viewfinder"
    // Auto-press sends input to the game, so the icon never looks off while it runs.
    dimmed = !readerEnabled && !autoPressOn
    toolTip =
      "Loupe: reader \(readerEnabled ? "on" : "off")" + (autoPressOn ? ", auto-press on" : "")
  }
}
