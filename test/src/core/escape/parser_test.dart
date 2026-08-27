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
  });
}
