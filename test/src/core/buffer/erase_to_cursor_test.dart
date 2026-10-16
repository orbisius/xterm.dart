import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  group('Erasing to the cursor', () {
    const erasedCodePoint = 0;
    final codePointB = 'b'.codeUnitAt(0);
    final codePointE = 'e'.codeUnitAt(0);
    final codePointX = 'X'.codeUnitAt(0);

    // EL1 erases from the start of the line THROUGH the cursor cell; stopping
    // one short leaves the character under the cursor on screen.
    test('EL1 erases the cursor cell too', () {
      final terminal = Terminal();

      terminal.write('abcdefgh\x1b[1;4H\x1b[1K');

      final firstLine = terminal.buffer.lines[0];
      final cursorCodePoint = firstLine.getCodePoint(3);
      final nextCodePoint = firstLine.getCodePoint(4);
      expect(cursorCodePoint, erasedCodePoint);
      expect(nextCodePoint, codePointE);
    });

    // ED1 erases the lines above and the current line through the cursor.
    test('ED1 erases the cursor cell too', () {
      final terminal = Terminal();

      terminal.write('top\r\nabcdefgh\x1b[2;4H\x1b[1J');

      final firstLine = terminal.buffer.lines[0];
      final secondLine = terminal.buffer.lines[1];
      final lineAboveCodePoint = firstLine.getCodePoint(0);
      final cursorCodePoint = secondLine.getCodePoint(3);
      final nextCodePoint = secondLine.getCodePoint(4);
      expect(lineAboveCodePoint, erasedCodePoint);
      expect(cursorCodePoint, erasedCodePoint);
      expect(nextCodePoint, codePointE);
    });

    // At column 0 the cursor cell is the whole range, so the first character
    // goes and the rest stays.
    test('EL1 at column 0 erases the first cell', () {
      final terminal = Terminal();

      terminal.write('abc\r\x1b[1K');

      final firstLine = terminal.buffer.lines[0];
      final cursorCodePoint = firstLine.getCodePoint(0);
      final nextCodePoint = firstLine.getCodePoint(1);
      expect(cursorCodePoint, erasedCodePoint);
      expect(nextCodePoint, codePointB);
    });

    // While a wrap is pending the cursor sits one past the last column. The
    // cells a line keeps beyond the view with reflow off must survive an
    // erase that reaches that far.
    test('EL1 with a wrap pending stays inside the view', () {
      final terminal = Terminal(reflowEnabled: false);
      terminal.write('HelloXWorld');
      terminal.resize(5, 5);

      terminal.write('\x1b[1;1HABCDE\x1b[1K');
      terminal.resize(20, 5);

      final firstLine = terminal.buffer.lines[0];
      final lastViewCodePoint = firstLine.getCodePoint(4);
      final hiddenCodePoint = firstLine.getCodePoint(5);
      expect(lastViewCodePoint, erasedCodePoint);
      expect(hiddenCodePoint, codePointX);
    });
  });
}
