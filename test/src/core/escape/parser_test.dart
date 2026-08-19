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
  });
}
