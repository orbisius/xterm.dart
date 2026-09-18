import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// PINS that erasing a row's TAIL does not un-wrap it.
///
/// `isWrapped` records how a row BEGAN — that the row above ran past the right
/// margin into it. Erasing from somewhere in the middle to the end of the line
/// changes what the row holds, never how it started, so the flag has to
/// survive.
///
/// It matters because `CSI K` is not an edge case: a full-screen program
/// appends it to nearly every row it paints, to clear whatever the previous
/// frame left there. Dropping the flag there means the terminal wraps a long
/// line correctly and then forgets, one escape sequence later, that it did —
/// and `getText` puts a newline in the middle of a line the screen shows as
/// one.
void main() {
  const eraseToLineEnd = '\x1b[K';

  /// A terminal narrow enough that one write wraps.
  Terminal buildTerminal() {
    final terminal = Terminal(maxLines: 100);

    terminal.resize(20, 6);

    return terminal;
  }

  test('erase-to-end-of-line keeps a wrapped row wrapped', () {
    final terminal = buildTerminal();

    // 28 characters into a 20-column terminal: the terminal itself wraps, and
    // the cursor ends on the second row, 8 columns in.
    terminal.write('y' * 28);

    expect(
      terminal.buffer.lines[1].isWrapped,
      isTrue,
      reason: 'the terminal wrapped this line',
    );

    terminal.write(eraseToLineEnd);

    expect(
      terminal.buffer.lines[1].isWrapped,
      isTrue,
      reason: 'erasing the tail of a row cannot change how the row began',
    );
  });

  test('a wrapped line survives the erase as ONE line of text', () {
    final terminal = buildTerminal();

    terminal.write('y' * 28);
    terminal.write(eraseToLineEnd);

    final range = BufferRangeLine(
      CellOffset(0, 0),
      CellOffset(8, 1),
    );

    final text = terminal.buffer.getText(range);

    expect(
      text,
      isNot(contains('\n')),
      reason: 'the screen shows one line, so a copy must hand back one line',
    );
  });

  test('erasing a row from column 0 DOES un-wrap it', () {
    final terminal = buildTerminal();

    terminal.write('y' * 28);

    // Back to the start of the continuation row, then erase it. That replaces
    // the row's beginning, which is exactly what the flag describes.
    terminal.write('\x1b[2;1H');
    terminal.write(eraseToLineEnd);

    expect(
      terminal.buffer.lines[1].isWrapped,
      isFalse,
      reason: 'the row no longer begins as a continuation of the one above',
    );
  });
}
