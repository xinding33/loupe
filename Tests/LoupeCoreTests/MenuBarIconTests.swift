import LoupeCore
import Testing

@Test func menuBarIconDimsOnlyWhenNothingIsRunning() {
  let reading = MenuBarIcon(readerEnabled: true, autoPressOn: false)
  #expect(reading.symbol == "viewfinder")
  #expect(!reading.dimmed)
  #expect(reading.toolTip == "Loupe: reader on")

  let off = MenuBarIcon(readerEnabled: false, autoPressOn: false)
  #expect(off.symbol == "viewfinder")
  #expect(off.dimmed)
  #expect(off.toolTip == "Loupe: reader off")
}

@Test func menuBarIconMarksAutoPressWhateverTheReaderIsDoing() {
  for reader in [true, false] {
    let icon = MenuBarIcon(readerEnabled: reader, autoPressOn: true)
    #expect(icon.symbol == "dot.viewfinder")
    #expect(!icon.dimmed)
    #expect(icon.toolTip.hasSuffix(", auto-press on"))
  }
}
