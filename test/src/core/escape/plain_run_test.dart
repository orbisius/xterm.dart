import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// The parser hands runs of plain ASCII to the buffer in one call instead of
/// one character at a time. These pin the boundaries of "plain": anything the
/// run path cannot handle has to fall back, invisibly, to the per-character
/// path.
void main() {
  group('plain ASCII runs', () {
    test('a run lands exactly as single writes would', () {
      final terminal = Terminal();
      terminal.resize(40, 10);

      terminal.write('hello world 123 !@#');

      expect(terminal.buffer.lines[0].toString(), 'hello world 123 !@#');
    });

    test('a run that reaches the margin wraps and continues', () {
      final terminal = Terminal();
      terminal.resize(10, 10);

      terminal.write('abcdefghijklmno');

      expect(terminal.buffer.lines[0].toString(), 'abcdefghij');
      expect(terminal.buffer.lines[1].toString(), 'klmno');
    });

    test('an escape inside the text still applies to what follows it', () {
      final terminal = Terminal();
      terminal.resize(40, 10);

      // Bold starts mid-text: the run before it must not pick up the style, and
      // the run after it must.
      terminal.write('plain\x1b[1mbold');

      final line = terminal.buffer.lines[0];
      final plainAttributes = line.getAttributes(0);
      final boldAttributes = line.getAttributes(5);

      expect(line.toString(), 'plainbold');
      expect(boldAttributes, isNot(plainAttributes));
    });

    test('a translating charset is not bypassed', () {
      final terminal = Terminal();
      terminal.resize(40, 10);

      // DEC special graphics maps ASCII letters to line-drawing glyphs. Those
      // code points are plain ASCII on the wire, so a run path that ignored the
      // charset would draw the letters instead of the box.
      terminal.write('\x1b(0');
      terminal.write('qqq');

      final drawn = terminal.buffer.lines[0].toString();

      expect(drawn, isNot('qqq'));
      expect(drawn.trim(), isNotEmpty);
    });

    test('non-ASCII text is unaffected', () {
      final terminal = Terminal();
      terminal.resize(40, 10);

      terminal.write('héllo — wörld');

      expect(terminal.buffer.lines[0].toString(), 'héllo — wörld');
    });

    test('a wide character keeps its second cell', () {
      final terminal = Terminal();
      terminal.resize(40, 10);

      terminal.write('ab你好cd');

      expect(terminal.buffer.lines[0].toString(), 'ab你好cd');
    });

    test('text split across writes joins up', () {
      // The run scan works within one queued block, so a character sequence
      // arriving in pieces must still land contiguously.
      final terminal = Terminal();
      terminal.resize(40, 10);

      terminal.write('abc');
      terminal.write('def');

      expect(terminal.buffer.lines[0].toString(), 'abcdef');
    });

    test('control characters inside the text keep their meaning', () {
      final terminal = Terminal();
      terminal.resize(40, 10);

      terminal.write('one\r\ntwo\ttab');

      expect(terminal.buffer.lines[0].toString(), 'one');
      expect(terminal.buffer.lines[1].toString(), startsWith('two'));
      expect(terminal.buffer.lines[1].toString(), endsWith('tab'));
    });
  });
}
