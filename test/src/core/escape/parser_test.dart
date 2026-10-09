import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';
import 'package:xterm/xterm.dart';

@GenerateNiceMocks([MockSpec<EscapeHandler>()])
import 'parser_test.mocks.dart';

void main() {
  group('EscapeParser', () {
    test('can parse window manipulation', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[8;24;80t');
      verify(parser.handler.resize(80, 24));
    });

    test('caps a parameter too long for an int instead of wrapping it', () {
      final parser = EscapeParser(MockEscapeHandler());

      // 2^64 - 1: past the largest 64-bit int, so reading it overflows.
      parser.write('\x1b[18446744073709551615M');

      verify(parser.handler.deleteLines(65535));
    });

    test('caps a REP count so the repeat ends', () {
      final parser = EscapeParser(MockEscapeHandler());

      // 2^63 - 1, the largest int: nothing overflows, so only a cap stops the
      // repeat.
      parser.write('x\x1b[9223372036854775807b');

      verify(parser.handler.repeatPreviousCharacter(65535));
    });

    test('passes a parameter under the cap through unchanged', () {
      final parser = EscapeParser(MockEscapeHandler());

      parser.write('\x1b[300S');

      verify(parser.handler.scrollUp(300));
    });

    test('reads a count of 0 as 1 in every count handler', () {
      final parser = EscapeParser(MockEscapeHandler());

      parser.write('\x1b[0L');
      verify(parser.handler.insertLines(1));

      parser.write('\x1b[0M');
      verify(parser.handler.deleteLines(1));

      parser.write('\x1b[0P');
      verify(parser.handler.deleteChars(1));

      parser.write('\x1b[0S');
      verify(parser.handler.scrollUp(1));

      parser.write('\x1b[0T');
      verify(parser.handler.scrollDown(1));

      parser.write('\x1b[0X');
      verify(parser.handler.eraseChars(1));

      parser.write('\x1b[0@');
      verify(parser.handler.insertBlankChars(1));

      parser.write('\x1b[0b');
      verify(parser.handler.repeatPreviousCharacter(1));

      parser.write('\x1b[0A');
      verify(parser.handler.moveCursorY(-1));

      parser.write('\x1b[0B');
      verify(parser.handler.moveCursorY(1));

      parser.write('\x1b[0C');
      verify(parser.handler.moveCursorX(1));

      parser.write('\x1b[0D');
      verify(parser.handler.moveCursorX(-1));

      parser.write('\x1b[0E');
      verify(parser.handler.cursorNextLine(1));

      parser.write('\x1b[0F');
      verify(parser.handler.cursorPrecedingLine(1));
    });

    test('reads a missing count as 1', () {
      final parser = EscapeParser(MockEscapeHandler());

      parser.write('\x1b[L');

      verify(parser.handler.insertLines(1));
    });
  });
}
