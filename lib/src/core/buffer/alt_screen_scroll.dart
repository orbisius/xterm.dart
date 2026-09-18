import 'package:xterm/src/core/buffer/line.dart';

/// One scroll of the alternate screen, reported as it happens.
///
/// The alternate screen keeps no scrollback, so a line pushed past the top of
/// the scrolled region is overwritten and gone. A host that wants to keep what
/// a full-screen program printed, or to keep a selection on the text it was
/// made on, has no other point at which the movement is knowable: the buffer
/// afterwards shows only the result, and nothing in the byte stream says how
/// far anything moved.
///
/// Both margins are SCREEN rows, so a host reads them against what it is
/// drawing. A region narrower than the screen is the normal case rather than
/// the exception — a full-screen program commonly pins a header or an input
/// box and scrolls only the rows between them, and rows outside [marginTop] ..
/// [marginBottom] did not move at all.
class AltScreenScroll {
  const AltScreenScroll({
    required this.marginTop,
    required this.marginBottom,
    required this.count,
    required this.lines,
  });

  /// First screen row of the region that scrolled.
  final int marginTop;

  /// Last screen row of the region that scrolled.
  final int marginBottom;

  /// How far the region moved, SIGNED: positive moved its rows UP, negative
  /// moved them DOWN. Never zero.
  ///
  /// One signed number rather than a distance plus a direction, so every
  /// consumer stays on the same arithmetic: a row lands at `row - count`
  /// whichever way the region went, and a host needs no branch to follow it.
  final int count;

  /// The lines the region lost, in SCREEN ORDER — topmost first.
  ///
  /// They leave from the edge the region moved away from: its first rows when
  /// [count] is positive, its last rows when negative. Screen order rather than
  /// order-of-loss so a host can lay them out without knowing the direction.
  ///
  /// They hold their content only until the caller returns — the buffer reuses
  /// the rows immediately after — so a host that keeps anything copies it here.
  /// Shorter than `count.abs()` when the region has fewer rows than it moved by.
  final List<BufferLine> lines;
}
