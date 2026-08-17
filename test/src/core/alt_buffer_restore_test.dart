import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/cell.dart';
import 'package:xterm/xterm.dart';

/// Leaving the alternate screen has to put back what entering it saved.
///
/// `?1049` is `?1047` plus `?1048`: the set arm saves the cursor and switches,
/// so the reset arm must switch back AND restore. Without the restore, whatever
/// text attributes a full-screen program was using when it exited stay active,
/// and the shell that comes back keeps drawing in them — the symptom being
/// every line rendering bold or underlined after a TUI quits.
void main() {
  int attributesAt(Terminal terminal, int index) {
    final line = terminal.buffer.lines[terminal.buffer.absoluteCursorY];
    final attributes = line.getAttributes(index);

    return attributes;
  }

  group('leaving the alternate screen', () {
    test('does not leak the underline a program left on', () {
      final terminal = Terminal();
      terminal.resize(40, 10);

      terminal.write('\x1b[?1049h'); // a TUI starts
      terminal.write('\x1b[4m'); // and turns on underline
      terminal.write('\x1b[?1049l'); // and quits without resetting it

      terminal.write('x');

      final attributes = attributesAt(terminal, 0);

      expect(attributes & CellFlags.underline, 0);
    });

    test('does not leak bold either', () {
      final terminal = Terminal();
      terminal.resize(40, 10);

      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[1m');
      terminal.write('\x1b[?1049l');

      terminal.write('x');

      final attributes = attributesAt(terminal, 0);

      expect(attributes & CellFlags.bold, 0);
    });

    test('keeps an attribute the shell itself had set', () {
      // The restore puts back the state from BEFORE the program ran, which is
      // not the same as clearing: a shell drawing its prompt in bold keeps it.
      final terminal = Terminal();
      terminal.resize(40, 10);

      terminal.write('\x1b[1m'); // the shell turns bold on
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[0m'); // the program resets everything
      terminal.write('\x1b[?1049l');

      terminal.write('x');

      final attributes = attributesAt(terminal, 0);

      expect(attributes & CellFlags.bold, CellFlags.bold);
    });

    test('puts the cursor back where the program found it', () {
      final terminal = Terminal();
      terminal.resize(40, 10);

      terminal.write('abc'); // cursor now at column 3
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[9;20H'); // the program moves it far away
      terminal.write('\x1b[?1049l');

      expect(terminal.buffer.cursorX, 3);
    });
  });
}
