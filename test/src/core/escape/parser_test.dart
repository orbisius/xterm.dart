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
  });
}
