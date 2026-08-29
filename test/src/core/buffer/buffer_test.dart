import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('Buffer.getText()', () {
    test('should return the text', () {
      final terminal = Terminal();
      terminal.write('Hello World');
      expect(terminal.buffer.getText(), startsWith('Hello World'));
    });

    test('can handle line wrap', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      final line1 = 'This is a long line that should wrap';
      final line2 = 'This is a short line';
      final line3 = 'This is a long long long long line that should wrap';
      final line4 = 'Short';

      terminal.write('$line1\r\n');
      terminal.write('$line2\r\n');
      terminal.write('$line3\r\n');
      terminal.write('$line4\r\n');

      final lines = terminal.buffer.getText().split('\n');
      expect(lines[0], line1);
      expect(lines[1], line2);
      expect(lines[2], line3);
      expect(lines[3], line4);
    });

    test('can handle negative start', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(-100, -100), CellOffset(100, 100)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle invalid end', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(0, 0), CellOffset(100, 100)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle reversed range', () {
      final terminal = Terminal();

      terminal.write('Hello World');

      expect(
        terminal.buffer.getText(
          BufferRangeLine(CellOffset(5, 5), CellOffset(0, 0)),
        ),
        startsWith('Hello World'),
      );
    });

    test('can handle block range', () {
      final terminal = Terminal();

      terminal.write('Hello World\r\n');
      terminal.write('Nice to meet you\r\n');

      expect(
        terminal.buffer.getText(
          BufferRangeBlock(CellOffset(2, 0), CellOffset(5, 1)),
        ),
        startsWith('llo\nce '),
      );
    });
  });

  group('Buffer.resize()', () {
    test('should resize the buffer', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      expect(terminal.viewWidth, 10);
      expect(terminal.viewHeight, 10);

      for (var i = 0; i < terminal.lines.length; i++) {
        final line = terminal.lines[i];
        expect(line.length, 10);
      }

      terminal.resize(20, 20);

      expect(terminal.viewWidth, 20);
      expect(terminal.viewHeight, 20);

      for (var i = 0; i < terminal.lines.length; i++) {
        final line = terminal.lines[i];
        expect(line.length, 20);
      }
    });
  });

  group('Buffer.deleteLines()', () {
    test('works', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      for (var i = 1; i <= 10; i++) {
        terminal.write('line$i');

        if (i < 10) {
          terminal.write('\r\n');
        }
      }

      terminal.setMargins(3, 7);
      terminal.setCursor(0, 5);

      terminal.buffer.deleteLines(1);

      expect(terminal.buffer.lines[2].toString(), 'line3');
      expect(terminal.buffer.lines[3].toString(), 'line4');
      expect(terminal.buffer.lines[4].toString(), 'line5');
      expect(terminal.buffer.lines[5].toString(), 'line7');
      expect(terminal.buffer.lines[6].toString(), 'line8');
      expect(terminal.buffer.lines[7].toString(), '');
      expect(terminal.buffer.lines[8].toString(), 'line9');
      expect(terminal.buffer.lines[9].toString(), 'line10');
    });
  });

  group('Buffer.insertLines()', () {
    test('works', () {
      final terminal = Terminal();

      for (var i = 0; i < 10; i++) {
        terminal.write('line$i\r\n');
      }

      print(terminal.buffer);

      terminal.setMargins(2, 6);
      terminal.setCursor(0, 4);

      print(terminal.buffer.absoluteCursorY);

      terminal.buffer.insertLines(1);

      print(terminal.buffer);

      expect(terminal.buffer.lines[3].toString(), 'line3');
      expect(terminal.buffer.lines[4].toString(), ''); // inserted
      expect(terminal.buffer.lines[5].toString(), 'line4'); // moved
      expect(terminal.buffer.lines[6].toString(), 'line5'); // moved
      expect(terminal.buffer.lines[7].toString(), 'line7');
    });

    test('has no effect if cursor is out of scroll region', () {
      final terminal = Terminal();

      for (var i = 0; i < 10; i++) {
        terminal.write('line$i\r\n');
      }

      terminal.setMargins(2, 6);
      terminal.setCursor(0, 1);

      terminal.buffer.insertLines(1);

      expect(terminal.buffer.lines[2].toString(), 'line2');
      expect(terminal.buffer.lines[3].toString(), 'line3');
      expect(terminal.buffer.lines[4].toString(), 'line4');
      expect(terminal.buffer.lines[5].toString(), 'line5');
      expect(terminal.buffer.lines[6].toString(), 'line6');
      expect(terminal.buffer.lines[7].toString(), 'line7');
    });
  });

  group('Buffer.getWordBoundary supports custom word separators', () {
    test('can set word separators', () {
      final terminal = Terminal(wordSeparators: {'o'.codeUnitAt(0)});

      terminal.write('Hello World');

      expect(
        terminal.mainBuffer.getWordBoundary(CellOffset(0, 0)),
        BufferRangeLine(CellOffset(0, 0), CellOffset(4, 0)),
      );

      expect(
        terminal.mainBuffer.getWordBoundary(CellOffset(5, 0)),
        BufferRangeLine(CellOffset(5, 0), CellOffset(7, 0)),
      );
    });
  });

  group('Buffer.getWordBoundary follows soft-wrapped lines', () {
    test('crosses the wrap edge forward from the first row', () {
      final terminal = Terminal();
      terminal.resize(20, 5);

      terminal.write('AB CDEFGHIJKLMNOPQRSTUVWXYZ');

      expect(terminal.buffer.lines[1].isWrapped, isTrue);

      final boundary = terminal.buffer.getWordBoundary(CellOffset(5, 0));

      expect(
        boundary,
        BufferRangeLine(CellOffset(3, 0), CellOffset(7, 1)),
      );

      expect(terminal.buffer.getText(boundary), 'CDEFGHIJKLMNOPQRSTUVWXYZ');
    });

    test('crosses the wrap edge backward from the continuation row', () {
      final terminal = Terminal();
      terminal.resize(20, 5);

      terminal.write('AB CDEFGHIJKLMNOPQRSTUVWXYZ');

      expect(terminal.buffer.lines[1].isWrapped, isTrue);

      final boundary = terminal.buffer.getWordBoundary(CellOffset(2, 1));

      expect(
        boundary,
        BufferRangeLine(CellOffset(3, 0), CellOffset(7, 1)),
      );

      expect(terminal.buffer.getText(boundary), 'CDEFGHIJKLMNOPQRSTUVWXYZ');
    });

    test('stops at a separator that ends the previous row', () {
      final terminal = Terminal();
      terminal.resize(20, 5);

      terminal.write('ABCDEFGHIJKLMNOPQRS VWXYZ');

      expect(terminal.buffer.lines[1].isWrapped, isTrue);

      final boundary = terminal.buffer.getWordBoundary(CellOffset(1, 1));

      expect(terminal.buffer.getText(boundary), 'VWXYZ');
    });

    test('follows a token across multiple wrapped rows', () {
      final terminal = Terminal();
      terminal.resize(10, 5);

      terminal.write('ABCDEFGHIJKLMNOPQRSTUVWXY');

      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(terminal.buffer.lines[2].isWrapped, isTrue);

      final boundary = terminal.buffer.getWordBoundary(CellOffset(5, 1));

      expect(
        boundary,
        BufferRangeLine(CellOffset(0, 0), CellOffset(5, 2)),
      );

      expect(terminal.buffer.getText(boundary), 'ABCDEFGHIJKLMNOPQRSTUVWXY');
    });

    test('a hard line break still stops the word', () {
      final terminal = Terminal();
      terminal.resize(20, 5);

      terminal.write('ABCDEFGH\r\nIJKL');

      expect(terminal.buffer.lines[1].isWrapped, isFalse);

      expect(
        terminal.buffer.getWordBoundary(CellOffset(2, 0)),
        BufferRangeLine(CellOffset(0, 0), CellOffset(8, 0)),
      );

      expect(
        terminal.buffer.getWordBoundary(CellOffset(1, 1)),
        BufferRangeLine(CellOffset(0, 1), CellOffset(4, 1)),
      );
    });
  });

  group('Buffer.getLineBoundary', () {
    test('selects the whole logical line from any of its rows', () {
      final terminal = Terminal();
      terminal.resize(20, 5);

      terminal.write('AB CDEFGHIJKLMNOPQRSTUVWXYZ');

      expect(terminal.buffer.lines[1].isWrapped, isTrue);

      final fromFirstRow = terminal.buffer.getLineBoundary(CellOffset(4, 0));

      expect(
        fromFirstRow,
        BufferRangeLine(CellOffset(0, 0), CellOffset(20, 1)),
      );

      final fromWrappedRow = terminal.buffer.getLineBoundary(CellOffset(3, 1));

      expect(
        fromWrappedRow,
        BufferRangeLine(CellOffset(0, 0), CellOffset(20, 1)),
      );

      expect(terminal.buffer.getText(fromFirstRow), 'AB CDEFGHIJKLMNOPQRSTUVWXYZ');
    });

    test('a hard-broken row is its own line', () {
      final terminal = Terminal();
      terminal.resize(20, 5);

      terminal.write('ABCDEFGH\r\nIJKL');

      expect(terminal.buffer.lines[1].isWrapped, isFalse);

      expect(
        terminal.buffer.getLineBoundary(CellOffset(0, 0)),
        BufferRangeLine(CellOffset(0, 0), CellOffset(20, 0)),
      );

      expect(
        terminal.buffer.getLineBoundary(CellOffset(2, 1)),
        BufferRangeLine(CellOffset(0, 1), CellOffset(20, 1)),
      );
    });

    test('follows a line across multiple wrapped rows', () {
      final terminal = Terminal();
      terminal.resize(10, 5);

      terminal.write('ABCDEFGHIJKLMNOPQRSTUVWXY');

      expect(terminal.buffer.lines[1].isWrapped, isTrue);
      expect(terminal.buffer.lines[2].isWrapped, isTrue);

      expect(
        terminal.buffer.getLineBoundary(CellOffset(3, 1)),
        BufferRangeLine(CellOffset(0, 0), CellOffset(10, 2)),
      );
    });
  });

  test('does not delete lines beyond the scroll region', () {
    final terminal = Terminal();
    terminal.resize(10, 10);

    for (var i = 1; i <= 10; i++) {
      terminal.write('line$i');

      if (i < 10) {
        terminal.write('\r\n');
      }
    }

    terminal.setMargins(3, 7);
    terminal.setCursor(0, 5);

    terminal.buffer.deleteLines(20);

    expect(terminal.buffer.lines[2].toString(), 'line3');
    expect(terminal.buffer.lines[3].toString(), 'line4');
    expect(terminal.buffer.lines[4].toString(), 'line5');
    expect(terminal.buffer.lines[5].toString(), '');
    expect(terminal.buffer.lines[6].toString(), '');
    expect(terminal.buffer.lines[7].toString(), '');
    expect(terminal.buffer.lines[8].toString(), 'line9');
    expect(terminal.buffer.lines[9].toString(), 'line10');
  });

  group('Buffer.eraseDisplayFromCursor()', () {
    test('works', () {
      final terminal = Terminal();
      terminal.resize(3, 3);
      terminal.write('123\r\n456\r\n789');

      terminal.setCursor(1, 1);
      terminal.buffer.eraseDisplayFromCursor();

      expect(terminal.buffer.lines[0].toString(), '123');
      expect(terminal.buffer.lines[1].toString(), '4');
      expect(terminal.buffer.lines[2].toString(), '');
    });
  });
}
