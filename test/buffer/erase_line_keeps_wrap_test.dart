import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// PINS what an erase does to the soft-wrap flag.
///
/// `isWrapped` sits on the row that CONTINUES: it records that the row above
/// ran past the right margin into this one. An erase that reaches the right
/// margin ends the line at the row it erases, so it clears the NEXT row's
/// flag. It never clears the erased row's own, because erasing a row cannot
/// change how that row began.
///
/// Both halves show up as a newline in the middle of a line the screen shows
/// as one. A full-screen program appends `CSI K` to nearly every row it
/// paints, and zsh erases and redraws a wrapped command line from column 0 of
/// the row the terminal wrapped it into.
void main() {
  const eraseToLineEnd = '\x1b[K';
  const eraseToLineStart = '\x1b[1K';
  const eraseWholeLine = '\x1b[2K';
  const eraseToScreenEnd = '\x1b[J';
  const eraseToScreenStart = '\x1b[1J';

  /// A terminal narrow enough that one write wraps.
  Terminal buildTerminal() {
    final terminal = Terminal(maxLines: 100);

    terminal.resize(20, 6);

    return terminal;
  }

  /// A terminal holding one line the terminal wrapped across three rows: rows
  /// 1 and 2 continue the row above them, and row 2 holds 5 characters.
  Terminal buildThreeRowLine() {
    final terminal = buildTerminal();

    terminal.write('y' * 45);

    expect(terminal.buffer.lines[1].isWrapped, isTrue);
    expect(terminal.buffer.lines[2].isWrapped, isTrue);

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

  test('erasing a row from column 0 keeps it joined to the row above', () {
    final terminal = buildTerminal();

    terminal.write('y' * 28);

    // Back to the start of the continuation row, then erase it. The row above
    // still runs into this one; only what this row holds is gone.
    terminal.write('\x1b[2;1H');
    terminal.write(eraseToLineEnd);

    expect(
      terminal.buffer.lines[1].isWrapped,
      isTrue,
      reason: 'erasing a row cannot change how the row began',
    );
  });

  test('zsh redrawing a wrapped command line keeps it ONE line', () {
    final terminal = buildTerminal();

    // What zsh writes after a `$ ` prompt when 30 characters are typed into
    // 20 columns, captured from `zsh -f -i` in a pty: it writes the character
    // past the margin itself so the terminal wraps, then goes back to column 0
    // of the new row, erases it and redraws it.
    terminal.write('\$ ');
    terminal.write('a\x08abcdefghijklmnopqr \r\x1b[Ks\rstuvwxyz0123');

    expect(
      terminal.buffer.lines[1].isWrapped,
      isTrue,
      reason: 'the terminal wrapped the line, and zsh only redrew its row',
    );

    final range = BufferRangeLine(
      CellOffset(0, 0),
      CellOffset(12, 1),
    );

    final text = terminal.buffer.getText(range);

    expect(text, '\$ abcdefghijklmnopqrstuvwxyz0123');
  });

  test('erasing a row mid-way ends the line there and keeps its own wrap', () {
    final terminal = buildThreeRowLine();

    // Row 1, column 5 (the sequence counts from 1).
    terminal.write('\x1b[2;6H');
    terminal.write(eraseToLineEnd);

    expect(
      terminal.buffer.lines[2].isWrapped,
      isFalse,
      reason: 'the end of row 1 is gone, so row 2 no longer follows on from it',
    );
    expect(
      terminal.buffer.lines[1].isWrapped,
      isTrue,
      reason: 'erasing the tail of a row cannot change how the row began',
    );

    final range = BufferRangeLine(
      CellOffset(0, 0),
      CellOffset(5, 2),
    );

    final text = terminal.buffer.getText(range);

    expect(text, startsWith('y' * 25));
    expect(text, endsWith('\nyyyyy'));
  });

  test('erasing a whole row ends the line there and keeps its own wrap', () {
    final terminal = buildThreeRowLine();

    terminal.write('\x1b[2;1H');
    terminal.write(eraseWholeLine);

    expect(
      terminal.buffer.lines[2].isWrapped,
      isFalse,
      reason: 'row 1 is blank, so row 2 no longer follows on from it',
    );
    expect(
      terminal.buffer.lines[1].isWrapped,
      isTrue,
      reason: 'erasing a row cannot change how the row began',
    );
  });

  test('erasing a row up to the cursor keeps every wrap', () {
    final terminal = buildThreeRowLine();

    terminal.write('\x1b[2;6H');
    terminal.write(eraseToLineStart);

    expect(
      terminal.buffer.lines[1].isWrapped,
      isTrue,
      reason: 'erasing a row cannot change how the row began',
    );
    expect(
      terminal.buffer.lines[2].isWrapped,
      isTrue,
      reason: 'the end of row 1 is still there, so row 2 still follows it',
    );
  });

  test('erasing the display from column 0 keeps the row joined above', () {
    final terminal = buildThreeRowLine();

    terminal.write('\x1b[2;1H');
    terminal.write(eraseToScreenEnd);

    expect(
      terminal.buffer.lines[1].isWrapped,
      isTrue,
      reason: 'the row above is untouched and still runs into this row',
    );
    expect(
      terminal.buffer.lines[2].isWrapped,
      isFalse,
      reason: 'everything from row 1 down is erased',
    );
  });

  test('erasing the display up to the cursor ends the line above it', () {
    final terminal = buildThreeRowLine();

    terminal.write('\x1b[2;6H');
    terminal.write(eraseToScreenStart);

    expect(
      terminal.buffer.lines[1].isWrapped,
      isFalse,
      reason: 'row 0 is erased whole, so nothing runs into row 1 any more',
    );
    expect(
      terminal.buffer.lines[2].isWrapped,
      isTrue,
      reason: 'the end of row 1 is still there, so row 2 still follows it',
    );
  });
}
