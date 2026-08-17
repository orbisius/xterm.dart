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

  group('scrollback recycling', () {
    /// A terminal whose scrollback is already full, so the next line feed is
    /// the one that evicts.
    Terminal buildFilledTerminal({required int maxLines}) {
      final terminal = Terminal(maxLines: maxLines);
      terminal.resize(20, 24);

      while (terminal.buffer.lines.length < maxLines) {
        terminal.write('fill\r\n');
      }

      return terminal;
    }

    test('reuses the evicted line object once the scrollback is full', () {
      final terminal = buildFilledTerminal(maxLines: 30);

      final oldest = terminal.buffer.lines[0];

      terminal.write('overflow\r\n');

      final newest = terminal.buffer.lines[terminal.buffer.lines.length - 1];
      expect(identical(newest, oldest), isTrue);
    });

    test('a recycled line shows none of the content it held', () {
      final terminal = Terminal(maxLines: 30);
      terminal.resize(20, 24);

      terminal.write('a very long first line\r\n');

      // Enough to walk the cursor to the bottom, fill the scrollback, and then
      // keep evicting: a line feed only adds a line once the cursor is at the
      // last row.
      for (var i = 1; i <= 60; i++) {
        terminal.write('x$i\r\n');
      }

      expect(terminal.buffer.getText(), isNot(contains('very long')));

      for (final line in terminal.buffer.lines.toList()) {
        expect(line.getTrimmedLength(), lessThanOrEqualTo(3));
      }
    });

    test('drops the anchors of the line it recycles', () {
      final terminal = Terminal(maxLines: 30);
      terminal.resize(20, 24);

      terminal.write('anchored\r\n');

      final anchor = terminal.buffer.lines[0].createAnchor(0);
      expect(anchor.attached, isTrue);

      // Enough to walk the cursor to the bottom, fill the scrollback, and then
      // keep evicting: a line feed only adds a line once the cursor is at the
      // last row.
      for (var i = 1; i <= 60; i++) {
        terminal.write('x$i\r\n');
      }

      // Same outcome as before recycling, when the evicted line was simply
      // dropped: an anchor whose content has scrolled out of history is no
      // longer attached to anything.
      expect(anchor.attached, isFalse);
    });

    test('keeps the visible text correct across many evictions', () {
      final terminal = Terminal(maxLines: 30);
      terminal.resize(20, 24);

      for (var i = 1; i <= 200; i++) {
        terminal.write('row$i\r\n');
      }

      final writtenLines = terminal.buffer
          .getText()
          .split('\n')
          .where((line) => line.isNotEmpty)
          .toList();

      expect(writtenLines.last, 'row200');
      expect(writtenLines.length, greaterThan(1));
    });
  });
}
