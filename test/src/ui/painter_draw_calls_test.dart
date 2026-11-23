import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/ui/render.dart';

/// How many draw calls a line costs: no paragraph for a space that shows
/// nothing, and one rectangle per run of cells that share a background.
///
/// Every frame redraws every visible line, and each paragraph and rectangle is
/// a call the raster thread works through. A program with its own color scheme
/// gives every cell a background, so a rectangle per cell is tens of thousands
/// of calls a frame.
void main() {
  /// Pumps a view over a terminal that has printed [output], with the cursor
  /// hidden so it adds no rectangle of its own.
  Future<RenderTerminal> pumpTerminal(
    WidgetTester tester,
    String output,
  ) async {
    final terminal = Terminal();
    terminal.write('\x1b[?25l$output');

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: TerminalView(terminal))),
    );

    final renderTerminals = tester.allRenderObjects.whereType<RenderTerminal>();
    final renderTerminal = renderTerminals.single;

    return renderTerminal;
  }

  group('text', () {
    testWidgets('a space that shows nothing draws no paragraph', (
      tester,
    ) async {
      final renderTerminal = await pumpTerminal(tester, 'a b c');

      expect(renderTerminal, paintsExactlyCountTimes(#drawParagraph, 3));
    });

    testWidgets('an underlined space still draws, for its underline', (
      tester,
    ) async {
      final renderTerminal = await pumpTerminal(tester, '\x1b[4ma b\x1b[0m');

      expect(renderTerminal, paintsExactlyCountTimes(#drawParagraph, 3));
    });
  });

  group('backgrounds', () {
    testWidgets('a run of cells on one background is one rectangle', (
      tester,
    ) async {
      final renderTerminal = await pumpTerminal(tester, '\x1b[41mabcdef\x1b[0m');

      expect(renderTerminal, paintsExactlyCountTimes(#drawRect, 1));
    });

    testWidgets('each background color gets its own rectangle', (
      tester,
    ) async {
      final renderTerminal = await pumpTerminal(
        tester,
        '\x1b[41mab\x1b[42mcd\x1b[0m e \x1b[41mf\x1b[0m',
      );

      expect(renderTerminal, paintsExactlyCountTimes(#drawRect, 3));
    });

    testWidgets('an inverse run is one rectangle in its foreground color', (
      tester,
    ) async {
      final renderTerminal = await pumpTerminal(
        tester,
        '\x1b[31;7mabc\x1b[0m',
      );

      final palette = TerminalThemes.defaultTheme;

      expect(renderTerminal, paintsExactlyCountTimes(#drawRect, 1));
      expect(renderTerminal, paints..rect(color: palette.red));
    });

    testWidgets('a run covers its cells and a wide character both of its own', (
      tester,
    ) async {
      final renderTerminal = await pumpTerminal(tester, '\x1b[41m中a\x1b[0m');

      final cellSize = renderTerminal.cellSize;

      // Three cells: the wide character's two and the "a". One pixel wider, so
      // no seam shows where a following rectangle begins.
      final expectedRect = Rect.fromLTWH(
        0,
        0,
        3 * cellSize.width + 1,
        cellSize.height,
      );

      expect(renderTerminal, paintsExactlyCountTimes(#drawRect, 1));
      expect(renderTerminal, paints..rect(rect: expectedRect));
    });
  });
}
