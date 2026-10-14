import 'package:test/test.dart';
import 'package:xterm/core.dart';

void main() {
  group('CursorStyle colors', () {
    final namedRed = NamedColor.red | CellColor.named;
    final namedBlue = NamedColor.blue | CellColor.named;

    // A palette index outside 0..255 has no palette entry to paint. The color
    // the program set before has to stay.
    test('keeps the current color when a palette index is out of range', () {
      final style = CursorStyle();
      style.setForegroundColor16(NamedColor.red);
      style.setBackgroundColor16(NamedColor.blue);

      style.setForegroundColor256(300);
      style.setBackgroundColor256(256);
      style.setForegroundColor256(-1);
      style.setBackgroundColor256(-1);

      expect(style.foreground, namedRed);
      expect(style.background, namedBlue);
    });

    // A component outside 0..255 spills into its neighbor or into the color
    // type, so the cell paints a color nobody asked for.
    test('keeps the current color when an RGB component is out of range', () {
      final style = CursorStyle();
      style.setForegroundColor16(NamedColor.red);
      style.setBackgroundColor16(NamedColor.blue);

      style.setForegroundColorRgb(512, 1, 0);
      style.setBackgroundColorRgb(0, 256, 0);
      style.setForegroundColorRgb(0, 0, -1);
      style.setBackgroundColorRgb(-1, 0, 0);

      expect(style.foreground, namedRed);
      expect(style.background, namedBlue);
    });

    // Both ends of the range are real colors, so the check must not be off by
    // one at either end.
    test('stores 0 and 255', () {
      final style = CursorStyle();
      final palette255 = 255 | CellColor.palette;
      final rgbWhite = 0xffffff | CellColor.rgb;

      style.setForegroundColor256(255);
      style.setBackgroundColor256(0);

      expect(style.foreground, palette255);
      expect(style.background, CellColor.palette);

      style.setForegroundColorRgb(255, 255, 255);
      style.setBackgroundColorRgb(0, 0, 0);

      expect(style.foreground, rgbWhite);
      expect(style.background, CellColor.rgb);
    });

    // The route a program takes: SGR through the parser. The cell must keep
    // the color that was set before the bad sequence arrived.
    test('an out-of-range SGR color leaves the cell color as it was', () {
      final terminal = Terminal();

      terminal.write('\x1b[31m\x1b[38;5;300m\x1b[48;2;512;0;0mX');

      final firstLine = terminal.buffer.lines[0];
      final cellForeground = firstLine.getForeground(0);
      final cellBackground = firstLine.getBackground(0);

      expect(cellForeground, namedRed);
      expect(cellBackground, CellColor.normal);
    });
  });
}
