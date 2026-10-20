import 'package:test/test.dart';
import 'package:xterm/core.dart';

const altScreenOn = '\x1b[?1049h';

const altScreenOff = '\x1b[?1049l';

/// Fits a 40-column row, not a 20-column one; every character differs, so a
/// cut or a reordering shows.
const thirtyCharacterText = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234';

/// A terminal showing its alternate screen, cursor at the top left.
Terminal buildAltTerminal({int maxLines = 100}) {
  final terminal = Terminal(maxLines: maxLines);

  terminal.resize(40, 10);
  terminal.write('$altScreenOn\x1b[H');

  return terminal;
}

/// Writes `<prefix> 0` … `<prefix> <count - 1>`, one per row, leaving the
/// cursor on the last of them.
void writeLines({
  required Terminal terminal,
  required String prefix,
  required int count,
}) {
  terminal.write('$prefix 0');

  for (var number = 1; number < count; number++) {
    terminal.write('\r\n$prefix $number');
  }
}

/// The text of buffer row [row], without the grid's unused tail.
String readRowText({required Terminal terminal, required int row}) {
  final line = terminal.buffer.lines[row];
  final lineText = line.getText();
  final trimmedText = lineText.trimRight();

  return trimmedText;
}

/// The line that starts on buffer row [firstRow], with every row after it the
/// terminal marked as its continuation — read the way a copy reads it.
String readJoinedRows({required Terminal terminal, required int firstRow}) {
  var lastRow = firstRow;
  var nextRow = firstRow + 1;

  while (nextRow < terminal.buffer.height) {
    final continuesLine = terminal.buffer.lines[nextRow].isWrapped;

    if (!continuesLine) {
      break;
    }

    lastRow = nextRow;
    nextRow++;
  }

  final range = BufferRangeLine(
    CellOffset(0, firstRow),
    CellOffset(terminal.viewWidth, lastRow),
  );

  final joinedText = terminal.buffer.getText(range);
  final trimmedText = joinedText.trimRight();

  return trimmedText;
}

/// PINS that the alternate screen keeps what scrolls off its top the way the
/// main screen does, so a host reads a full-screen program's output from the
/// buffer instead of keeping a copy of its own beside it.
///
/// Destroying those lines left a host two choices, both wrong: call one screen
/// the output, or record each line as it scrolls off — a second history that
/// loses the wrap flag and cannot be painted, selected or searched.
void main() {
  group('the alternate screen keeps what scrolls off its top', () {
    // Ten rows, fifteen lines: the five that left the screen are still there,
    // oldest first, above it.
    test('a line feed at the bottom keeps the top line', () {
      final terminal = buildAltTerminal();

      writeLines(terminal: terminal, prefix: 'line', count: 15);

      expect(terminal.buffer.scrollBack, 5);
      expect(readRowText(terminal: terminal, row: 0), 'line 0');
      expect(readRowText(terminal: terminal, row: 5), 'line 5');
    });

    // A long line the terminal wrapped must come back as ONE line once it is
    // in the history — the wrap flag travels with the line.
    test('a wrapped line is kept as one line', () {
      final terminal = buildAltTerminal();

      const wideText = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'BBBBBBBBBBBBBBBBBBBB';

      terminal.write('$wideText\r\n');

      writeLines(terminal: terminal, prefix: 'after', count: 10);

      final wrappedRange = BufferRangeLine(
        const CellOffset(0, 0),
        CellOffset(terminal.viewWidth, 1),
      );

      final keptText = terminal.buffer.getText(wrappedRange);
      final trimmedKeptText = keptText.trimRight();

      expect(terminal.buffer.scrollBack, 2);
      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(trimmedKeptText, wideText);
    });

    // An input box below the scrolling rows is not output: the rows above it
    // go into the history, the box stays at the bottom of the screen.
    test('rows below a region that starts at the top stay on screen', () {
      final terminal = buildAltTerminal();

      terminal.write('\x1b[1;8r');
      terminal.write('\x1b[9;1Hbox top\x1b[10;1Hbox end');
      terminal.write('\x1b[8;1H');

      writeLines(terminal: terminal, prefix: 'msg', count: 21);

      final screenTop = terminal.buffer.scrollBack;

      expect(screenTop, 20);
      expect(readRowText(terminal: terminal, row: screenTop + 7), 'msg 20');
      expect(readRowText(terminal: terminal, row: screenTop + 8), 'box top');
      expect(readRowText(terminal: terminal, row: screenTop + 9), 'box end');
    });

    // The ceiling is the one the main screen already has, so a program that
    // streams for hours cannot grow the buffer without bound.
    test('the history is capped by maxLines, oldest out first', () {
      final terminal = buildAltTerminal(maxLines: 30);

      writeLines(terminal: terminal, prefix: 'line', count: 100);

      expect(terminal.buffer.height, 30);
      expect(readRowText(terminal: terminal, row: 0), 'line 70');
      expect(readRowText(terminal: terminal, row: 29), 'line 99');
    });

    // Splitting a pane, zooming the font or moving the window to another
    // monitor resizes the terminal while the program runs. Losing the history
    // to it would make the copy depend on whether the user touched the layout.
    test('a resize keeps the history', () {
      final terminal = buildAltTerminal();

      writeLines(terminal: terminal, prefix: 'line', count: 15);

      terminal.resize(40, 8);

      expect(readRowText(terminal: terminal, row: 0), 'line 0');

      terminal.resize(50, 10);

      expect(readRowText(terminal: terminal, row: 0), 'line 0');
    });

    // A new line belongs only where the program sent one: a kept line that no
    // longer fits must stay ONE line, or a copy of a long command comes back
    // cut — and pasted, runs on the cut half.
    test('a narrower pane rewraps a kept line instead of cutting it', () {
      final terminal = buildAltTerminal();

      terminal.write('$thirtyCharacterText\r\n');

      writeLines(terminal: terminal, prefix: 'after', count: 10);

      expect(terminal.buffer.scrollBack, 1, reason: 'the long line is kept');

      terminal.resize(20, 10);

      final keptText = readJoinedRows(terminal: terminal, firstRow: 0);

      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(keptText, thirtyCharacterText);

      terminal.resize(40, 10);

      expect(
        readRowText(terminal: terminal, row: 0),
        thirtyCharacterText,
        reason: 'widened again, it fits on one row',
      );
    });

    test('a narrower pane rewraps a line still on screen too', () {
      final terminal = buildAltTerminal();

      terminal.write(thirtyCharacterText);

      terminal.resize(20, 10);

      final screenText = readJoinedRows(terminal: terminal, firstRow: 0);

      expect(screenText, thirtyCharacterText);
    });
  });

  group('what the alternate screen does NOT keep', () {
    // Rows above the region never move, so nothing leaves the screen: the
    // line pushed out of the region is overwritten, as before.
    test('a region that starts below the top keeps nothing', () {
      final terminal = buildAltTerminal();

      terminal.write('header');
      terminal.write('\x1b[2;10r\x1b[10;1H');

      writeLines(terminal: terminal, prefix: 'body', count: 15);

      expect(terminal.buffer.scrollBack, 0);
      expect(readRowText(terminal: terminal, row: 0), 'header');
      expect(
        readRowText(terminal: terminal, row: 9),
        'body 14',
        reason: 'the region did scroll',
      );
    });

    // Each program run starts clean, so one program's output never shows up
    // as the next one's.
    test('entering the alternate screen again starts with no history', () {
      final terminal = buildAltTerminal();

      writeLines(terminal: terminal, prefix: 'first run', count: 15);

      expect(
        terminal.buffer.scrollBack,
        5,
        reason: 'the first run kept lines for the switch to clear',
      );

      terminal.write('$altScreenOff$altScreenOn');

      expect(terminal.buffer.scrollBack, 0);
    });
  });
}
