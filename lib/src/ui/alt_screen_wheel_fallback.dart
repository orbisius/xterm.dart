/// Where a wheel turn goes on the alternate screen when the program running
/// there did not ask for it — it turned on neither mouse reporting nor
/// DECSET 1007. A program that asked always gets the wheel.
enum AltScreenWheelFallback {
  /// Scroll the lines the alternate screen kept above it, the way the main
  /// screen scrolls its scrollback.
  scrollHistory,

  /// Hand the wheel to the program anyway, as arrow keys when
  /// `TerminalView.simulateScroll` is on.
  sendToProgram,
}
