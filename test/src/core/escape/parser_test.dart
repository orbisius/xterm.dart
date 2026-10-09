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

    // SGR 22 is "normal intensity", which ends bold as well as faint. Missing
    // the bold half leaves the terminal permanently bold once any program
    // uses the standard bold-then-normal pair.
    test('SGR 22 ends both bold and faint', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[1mbold\x1b[22m');
      verify(parser.handler.setCursorBold());
      verify(parser.handler.unsetCursorBold());
      verify(parser.handler.unsetCursorFaint());
    });

    // A colon separates SUB-parameters (ECMA-48 / ITU-T T.416). Skipping it lets
    // the digits after it land on the parameter before it, so `4:0` — the modern
    // spelling of "underline off" — arrives as SGR 40 and the underline is never
    // cleared. Every line drawn afterwards is then underlined.
    test('SGR 4:0 ends underlining', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[4m\x1b[4:0m');
      verify(parser.handler.setCursorUnderline());
      verify(parser.handler.unsetCursorUnderline());
      verifyNever(parser.handler.setBackgroundColor16(NamedColor.black));
    });

    // The style selectors all underline; only the flag is modelled, but none of
    // them may be mistaken for a background colour.
    test('SGR 4:3 underlines rather than setting a background', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[4:3m');
      verify(parser.handler.setCursorUnderline());
      verifyNever(parser.handler.setBackgroundColor16(NamedColor.yellow));
    });

    test('a sub-parameter cannot leak into the NEXT parameter', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[4:3;1m');
      verify(parser.handler.setCursorUnderline());
      verify(parser.handler.setCursorBold());
    });

    test('extended colour is read in both the colon and semicolon forms', () {
      final semicolons = EscapeParser(MockEscapeHandler());
      semicolons.write('\x1b[38;2;255;0;0m');
      verify(semicolons.handler.setForegroundColorRgb(255, 0, 0));

      final colons = EscapeParser(MockEscapeHandler());
      colons.write('\x1b[38:2::255:0:0m');
      verify(colons.handler.setForegroundColorRgb(255, 0, 0));

      final palette = EscapeParser(MockEscapeHandler());
      palette.write('\x1b[48:5:196m');
      verify(palette.handler.setBackgroundColor256(196));
    });

    // A program can send a truncated selector; reading past the end of the
    // parameter list for its missing components throws a RangeError. Reaching
    // the end of this test at all is the assertion.
    test('a truncated extended colour applies nothing and does not throw', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[38m\x1b[38;2;255m\x1b[48;5m\x1b[38:2m');
      verifyNever(parser.handler.setForegroundColorRgb(255, 0, 0));
    });

    // `CSI > Pp ; Pv m` is XTMODKEYS — keyboard configuration, not SGR. Read
    // as SGR its `4` underlines: applications reset modifyOtherKeys on exit
    // with `CSI > 4 m`, which painted everything after them underlined.
    test('XTMODKEYS (CSI > 4 m) is not read as SGR underline', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[>4m');
      verifyNever(parser.handler.setCursorUnderline());
    });

    test('XTMODKEYS with a value (CSI > 4;2 m) sets no styling either', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[>4;2m');
      verifyNever(parser.handler.setCursorUnderline());
      verifyNever(parser.handler.setCursorFaint());
    });

    test('a prefixed m does not disturb the styling around it', () {
      final parser = EscapeParser(MockEscapeHandler());
      parser.write('\x1b[4m\x1b[>4m\x1b[24m');
      verify(parser.handler.setCursorUnderline()).called(1);
      verify(parser.handler.unsetCursorUnderline()).called(1);
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
