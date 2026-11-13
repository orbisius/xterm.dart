import 'package:test/test.dart';
import 'package:xterm/core.dart';
import 'package:xterm/ui.dart';

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

/// Draws `<prefix> 0` … `<prefix> <rowCount - 1>` on the screen's top rows the
/// way a full-screen program paints a frame — each row placed by a cursor move,
/// no line feed — then leaves the cursor on screen row [cursorRow].
void writeFrame({
  required Terminal terminal,
  required String prefix,
  required int rowCount,
  required int cursorRow,
}) {
  for (var row = 0; row < rowCount; row++) {
    terminal.write('\x1b[${row + 1};1H\x1b[2K$prefix $row');
  }

  terminal.write('\x1b[${cursorRow + 1};1H');
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

  // A resize rebuilds the screen, and the program repaints it afterwards. The
  // rows the new size no longer fits are a copy of an old frame, not output, so
  // they are dropped, as iTerm2 does; kept in the history, every split or font
  // zoom would stack another stale frame above the program's real output.
  group('a resize drops the screen rows it no longer fits', () {
    test('a shorter screen drops its frame instead of keeping it', () {
      final terminal = buildAltTerminal();

      writeFrame(terminal: terminal, prefix: 'old', rowCount: 10, cursorRow: 9);

      terminal.resize(40, 4);

      writeFrame(terminal: terminal, prefix: 'new', rowCount: 4, cursorRow: 3);

      expect(terminal.buffer.scrollBack, 0);
      expect(terminal.buffer.height, 4);
      expect(readRowText(terminal: terminal, row: 0), 'new 0');
    });

    test('a shorter screen keeps the history it had and the cursor row', () {
      final terminal = buildAltTerminal();

      writeLines(terminal: terminal, prefix: 'line', count: 15);

      terminal.resize(40, 6);

      expect(terminal.buffer.scrollBack, 5, reason: 'line 0 to line 4');
      expect(readRowText(terminal: terminal, row: 4), 'line 4');
      expect(readRowText(terminal: terminal, row: 5), 'line 9');
      expect(readRowText(terminal: terminal, row: 10), 'line 14');
      expect(terminal.buffer.cursorY, 5);
    });

    test('a narrower screen drops the rows its rewrap no longer fits', () {
      final terminal = buildAltTerminal();

      for (var row = 0; row < 10; row++) {
        terminal.write('\x1b[${row + 1};1H$row$thirtyCharacterText');
      }

      terminal.resize(20, 10);

      final lastRowText = readJoinedRows(terminal: terminal, firstRow: 8);

      expect(terminal.buffer.scrollBack, 0);
      expect(lastRowText, '9$thirtyCharacterText');
      expect(
        terminal.buffer.cursorX,
        11,
        reason: 'the cursor stays after the last character, on its new row',
      );
      expect(terminal.buffer.cursorY, 9);
    });

    // Blank rows below the cursor are room, not content: a rewrap fills them
    // before it drops anything a program drew.
    test('a narrower screen fills the blank rows before it drops any', () {
      final terminal = buildAltTerminal();

      for (var row = 0; row < 3; row++) {
        terminal.write('\x1b[${row + 1};1H$row$thirtyCharacterText');
      }

      terminal.resize(20, 10);

      final firstRowText = readJoinedRows(terminal: terminal, firstRow: 0);

      expect(terminal.buffer.scrollBack, 0);
      expect(firstRowText, '0$thirtyCharacterText');
    });

    // Growing the screen into the history would hand kept output to the
    // program to paint over, so a later shrink would drop it for good.
    test('a taller screen keeps the history as history', () {
      final terminal = buildAltTerminal();

      writeLines(terminal: terminal, prefix: 'line', count: 15);

      terminal.resize(40, 12);

      expect(terminal.buffer.scrollBack, 5, reason: 'line 0 to line 4');
      expect(readRowText(terminal: terminal, row: 5), 'line 5');
      expect(readRowText(terminal: terminal, row: 14), 'line 14');
      expect(terminal.buffer.cursorY, 9);
    });

    // A kept line whose end ran onto the screen is output: the rows dropped
    // must come from below it, or the copy loses a line it showed.
    test('a kept line that ran onto the screen stays whole', () {
      final terminal = buildAltTerminal();

      const wideText = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'
          'BBBBBBBBBBBBBBBBBBBB';

      terminal.write('$wideText\r\n');

      writeLines(terminal: terminal, prefix: 'after', count: 9);

      expect(
        terminal.buffer.scrollBack,
        1,
        reason: 'the line starts above the screen and ends on its first row',
      );

      terminal.resize(80, 5);

      expect(terminal.buffer.scrollBack, 1);
      expect(readRowText(terminal: terminal, row: 0), wideText);
      expect(readRowText(terminal: terminal, row: 1), 'after 4');
      expect(readRowText(terminal: terminal, row: 5), 'after 8');
    });

    test('the main screen still keeps what a resize moves off its top', () {
      final terminal = Terminal(maxLines: 100);

      terminal.resize(40, 10);
      writeLines(terminal: terminal, prefix: 'line', count: 10);

      terminal.resize(40, 6);

      expect(terminal.buffer.scrollBack, 4);
      expect(readRowText(terminal: terminal, row: 0), 'line 0');
    });
  });

  // A pane split or a monitor change resizes the terminal while something is
  // selected. The selection's rows stay, above the screen when they no longer
  // fit, so the highlight survives and a copy still reads what was chosen.
  group('a resize keeps the rows a selection sits on', () {
    test("a shrink keeps the rows from the selection's row down", () {
      final terminal = buildAltTerminal();
      final controller = TerminalController();

      writeFrame(terminal: terminal, prefix: 'old', rowCount: 10, cursorRow: 9);

      final buffer = terminal.buffer;

      controller.setSelection(
        buffer.createAnchor(0, 2),
        buffer.createAnchor(5, 3),
      );

      terminal.resize(40, 4);

      final selection = controller.selection;

      expect(selection, isNotNull, reason: 'its anchors are still attached');
      expect(selection?.begin.y, 0);
      expect(selection?.end.y, 1);
      expect(
        terminal.buffer.scrollBack,
        4,
        reason: 'old 2 to old 5 sit above the screen',
      );
      expect(readRowText(terminal: terminal, row: 0), 'old 2');
      expect(readRowText(terminal: terminal, row: 4), 'old 6');
      expect(terminal.buffer.cursorY, 3);
    });

    // The rewrap moves each anchor onto the row its text lands on, and the
    // drop stops there, not at the row the anchor sat on before.
    test("a narrower screen keeps the selection's rewrapped rows", () {
      final terminal = buildAltTerminal();
      final controller = TerminalController();

      for (var row = 0; row < 10; row++) {
        terminal.write('\x1b[${row + 1};1H$row$thirtyCharacterText');
      }

      final buffer = terminal.buffer;

      controller.setSelection(
        buffer.createAnchor(0, 1),
        buffer.createAnchor(10, 1),
      );

      terminal.resize(20, 10);

      final selection = controller.selection;

      expect(selection, isNotNull, reason: 'its anchors are still attached');
      expect(selection?.begin.y, 0);
      expect(terminal.buffer.scrollBack, 8);
      expect(
        readJoinedRows(terminal: terminal, firstRow: 0),
        '1$thirtyCharacterText',
      );
    });

    test('a selection still on the new screen changes nothing', () {
      final terminal = buildAltTerminal();
      final controller = TerminalController();

      writeFrame(terminal: terminal, prefix: 'old', rowCount: 10, cursorRow: 9);

      final buffer = terminal.buffer;

      controller.setSelection(
        buffer.createAnchor(0, 8),
        buffer.createAnchor(5, 9),
      );

      terminal.resize(40, 4);

      final selection = controller.selection;

      expect(terminal.buffer.scrollBack, 0);
      expect(readRowText(terminal: terminal, row: 0), 'old 6');
      expect(selection?.begin.y, 2);
    });

    // A host keeps anchors of its own, such as where a later Shift+click
    // reaches from. Keeping their rows would bring the old frame back after
    // almost any click.
    test("an anchor that is not a selection's keeps nothing", () {
      final terminal = buildAltTerminal();

      writeFrame(terminal: terminal, prefix: 'old', rowCount: 10, cursorRow: 9);

      final anchor = terminal.buffer.createAnchor(0, 2);

      terminal.resize(40, 4);

      expect(terminal.buffer.scrollBack, 0);
      expect(readRowText(terminal: terminal, row: 0), 'old 6');
      expect(anchor.attached, isFalse, reason: 'its row was dropped');
    });

    test('a cleared selection keeps nothing', () {
      final terminal = buildAltTerminal();
      final controller = TerminalController();

      writeFrame(terminal: terminal, prefix: 'old', rowCount: 10, cursorRow: 9);

      final buffer = terminal.buffer;

      controller.setSelection(
        buffer.createAnchor(0, 2),
        buffer.createAnchor(5, 3),
      );
      controller.clearSelection();

      terminal.resize(40, 4);

      expect(terminal.buffer.scrollBack, 0);
      expect(readRowText(terminal: terminal, row: 0), 'old 6');
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
