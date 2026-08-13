enum TerminalMouseButton {
  left(id: 0),

  middle(id: 1),

  right(id: 2),

  wheelUp(id: 64 + 0, isWheel: true),

  wheelDown(id: 64 + 1, isWheel: true),

  wheelLeft(id: 64 + 2, isWheel: true),

  wheelRight(id: 64 + 3, isWheel: true),
  ;

  /// The id that is used to report a button press or release to the terminal.
  ///
  /// Wheel buttons are X buttons 4-7, but they are NOT reported as 4-7. Per
  /// xterm's ctlseqs, they reuse the event codes of buttons 1-4 — that is 0-3 —
  /// with 64 added. So wheel up is 64, not 68.
  ///
  /// The distinction is not cosmetic: 4, 8 and 16 are the Shift, Meta and
  /// Control modifier bits. Adding 64 to the raw button number sets those bits,
  /// so a plain wheel turn reports as "wheel with Shift held" and programs that
  /// scroll on the wheel ignore it entirely.
  final int id;

  /// Whether this button is a mouse wheel button.
  final bool isWheel;

  const TerminalMouseButton({required this.id, this.isWheel = false});
}
