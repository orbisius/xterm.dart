import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  group('Erasing a range of cells', () {
    final wideCodePoint = '中'.codeUnitAt(0);

    // An empty range has nothing to erase, so it must not read before the
    // line — at column 0 that throws out of Terminal.write.
    test('an empty range at column 0 erases nothing', () {
      final terminal = Terminal();
      terminal.write('abc\r');

      terminal.eraseChars(0);

      final firstLine = terminal.buffer.lines[0];
      final lineText = firstLine.getText();
      expect(lineText, 'abc');
    });

    // An empty range that starts on a wide character's right half must not
    // reach over and erase the character.
    test('an empty range on a wide character leaves the character', () {
      final terminal = Terminal();
      terminal.write('中x\x1b[1;2H');

      terminal.eraseChars(0);

      final firstLine = terminal.buffer.lines[0];
      final firstCodePoint = firstLine.getCodePoint(0);
      expect(firstCodePoint, wideCodePoint);
    });

    // The sequences that reach an empty range. A throw abandons the rest of
    // the chunk, so the text after the erase has to land.
    test('EL1, ED1 and ECH 0 at column 0 keep the output after them', () {
      final sequences = [
        'abc\r\x1b[1KXYZ',
        'abc\x1b[H\x1b[1JXYZ',
        'abc\r\x1b[0XXYZ',
      ];

      for (final sequence in sequences) {
        final terminal = Terminal();
        terminal.write(sequence);

        final firstLine = terminal.buffer.lines[0];
        final lineText = firstLine.getText();
        expect(lineText, 'XYZ', reason: sequence);
      }
    });

    // A wide character occupies two cells, so erasing either half has to
    // clear both, or the other half keeps the old style.
    test("erasing a wide character's left half clears its right half", () {
      final terminal = Terminal();
      terminal.write('\x1b[41m中\x1b[0m\r\x1b[1X');

      final firstLine = terminal.buffer.lines[0];
      final rightHalfBackground = firstLine.getBackground(1);
      expect(rightHalfBackground, CellColor.normal);
    });

    test("erasing a wide character's right half clears its left half", () {
      final terminal = Terminal();
      terminal.write('\x1b[41m中\x1b[0m\x1b[1;2H\x1b[1X');

      final firstLine = terminal.buffer.lines[0];
      final leftHalfBackground = firstLine.getBackground(0);
      expect(leftHalfBackground, CellColor.normal);
    });
  });
}
