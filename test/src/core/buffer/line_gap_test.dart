import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// A terminal wide enough that nothing under test wraps by accident.
Terminal buildTerminal() {
  final terminal = Terminal(maxLines: 100);

  terminal.resize(80, 24);

  return terminal;
}

/// The first row of [terminal]'s buffer, with the row's unused tail removed.
///
/// The split is on a LINE FEED and that is not platform-dependent: the buffer is
/// an in-memory grid, and [Buffer.getText] writes "\n" between rows itself. A
/// platform-aware split would be the bug — on Windows nothing would match.
String readFirstLine(Terminal terminal) {
  final bufferText = terminal.buffer.getText();

  final lines = bufferText.split('\n');

  final firstLine = lines.first;

  final trimmed = firstLine.trimRight();

  return trimmed;
}

void main() {
  group('copying text a program laid out with cursor moves', () {
    test('a cursor-positioned gap copies as a space, not nothing', () {
      // How a TUI actually draws: write a word, JUMP the cursor, write the
      // next. The cells in between are never touched.
      final terminal = buildTerminal();

      terminal.write('cmd\x1b[5G-r123');

      final text = readFirstLine(terminal);

      expect(
        text,
        equals('cmd -r123'),
        reason: 'closing the gap would paste a different command',
      );
    });

    test('a wider gap keeps every column', () {
      final terminal = buildTerminal();

      terminal.write('a\x1b[6Gb');

      final text = readFirstLine(terminal);

      expect(text, equals('a    b'));
    });

    test('a gap at the START of a line is kept', () {
      // Indentation drawn by moving the cursor rather than by writing spaces —
      // losing it would silently re-indent copied code.
      final terminal = buildTerminal();

      terminal.write('\x1b[5Gindented');

      final text = readFirstLine(terminal);

      expect(text, equals('    indented'));
    });

    test('several gaps on one line all survive', () {
      final terminal = buildTerminal();

      terminal.write('a\x1b[4Gb\x1b[7Gc');

      final text = readFirstLine(terminal);

      expect(text, equals('a  b  c'));
    });

    test('an emoji is not mistaken for a gap', () {
      // The trap: one emoji spans TWO cells and the second reads as unwritten,
      // exactly like a gap. Treating it as one puts a space inside every emoji
      // run — which is how a naive version of this fix breaks copy for anyone
      // whose output has emoji in it.
      final terminal = buildTerminal();

      terminal.write('😀😁 done');

      final text = readFirstLine(terminal);

      expect(text, equals('😀😁 done'));
    });

    test('CJK characters are not mistaken for gaps either', () {
      // Same two-cell rule as emoji, and far more likely to appear in ordinary
      // output than an emoji run.
      final terminal = buildTerminal();

      terminal.write('日本語 text');

      final text = readFirstLine(terminal);

      expect(text, equals('日本語 text'));
    });

    test('a wide character straight after a gap keeps both', () {
      // The two rules meet: a gap must become a space AND the wide character
      // after it must stay whole.
      final terminal = buildTerminal();

      terminal.write('a\x1b[4G日本');

      final text = readFirstLine(terminal);

      expect(text, equals('a  日本'));
    });

    test('a row still copies without its unused tail', () {
      // The other half of the rule: only gaps BETWEEN written cells become
      // spaces. Padding every line out to the terminal's width would be its own
      // bug, and every existing caller depends on that not happening.
      final terminal = buildTerminal();

      terminal.write('short');

      final bufferText = terminal.buffer.getText();

      final lines = bufferText.split('\n');

      final firstLine = lines.first;

      expect(firstLine, equals('short'));
    });

    test('a line that was never written copies as nothing', () {
      final terminal = buildTerminal();

      final bufferText = terminal.buffer.getText();

      final lines = bufferText.split('\n');

      final firstLine = lines.first;

      expect(firstLine, isEmpty);
    });

    test('a gap survives a line that WRAPS', () {
      // Wrapped rows rejoin with no separator, so a gap sitting at the wrap
      // boundary is the easiest one to lose — and long command suggestions are
      // exactly the text that wraps.
      final terminal = Terminal(maxLines: 100);

      terminal.resize(10, 24);

      // Fills the row, then continues past its width so the line wraps.
      terminal.write('abcdefgh\x1b[12Gtail');

      final bufferText = terminal.buffer.getText();

      final lines = bufferText.split('\n');

      final firstLine = lines.first;

      expect(firstLine, contains('abcdefgh'));
      expect(firstLine, contains('tail'));
      expect(firstLine, isNot(contains('abcdefghtail')));
    });
  });
}
