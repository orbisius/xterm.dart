import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/ui/render.dart';

/// How many draw calls a line costs: one paragraph per run of same-style
/// printable ASCII, nothing for blank spaces at a run's ends, and one rectangle
/// per run of cells that share a background.
///
/// Every frame redraws every visible line, and each paragraph and rectangle is
/// a call the raster thread works through. A screen of text is thousands of
/// characters, and a program with its own color scheme gives every cell a
/// background.
void main() {
  /// Pumps a view over a terminal that has printed [output], with the cursor
  /// hidden so it adds no rectangle of its own.
  Future<RenderTerminal> pumpTerminal(
    WidgetTester tester,
    String output, {
    TerminalStyle textStyle = const TerminalStyle(),
  }) async {
    final terminal = Terminal();
    terminal.write('\x1b[?25l$output');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TerminalView(terminal, textStyle: textStyle)),
      ),
    );

    final renderTerminals = tester.allRenderObjects.whereType<RenderTerminal>();
    final renderTerminal = renderTerminals.single;

    return renderTerminal;
  }

  group('text', () {
    testWidgets('a run of one style is one paragraph, inner spaces included', (
      tester,
    ) async {
      final renderTerminal = await pumpTerminal(tester, 'hello world');

      expect(renderTerminal, paintsExactlyCountTimes(#drawParagraph, 1));
    });

    testWidgets('a blank space on its own draws nothing', (tester) async {
      final renderTerminal = await pumpTerminal(tester, ' ');

      expect(renderTerminal, paintsExactlyCountTimes(#drawParagraph, 0));
    });

    testWidgets('an underlined space draws, for its underline', (
      tester,
    ) async {
      final renderTerminal = await pumpTerminal(tester, '\x1b[4m \x1b[0m');

      expect(renderTerminal, paintsExactlyCountTimes(#drawParagraph, 1));
    });

    testWidgets('a change of style or color starts a new run', (tester) async {
      final renderTerminal = await pumpTerminal(
        tester,
        'ab\x1b[1mcd\x1b[31mef\x1b[0m',
      );

      expect(renderTerminal, paintsExactlyCountTimes(#drawParagraph, 3));
    });

    testWidgets('a wide character keeps its own cell', (tester) async {
      final renderTerminal = await pumpTerminal(tester, 'ab中cd');

      expect(renderTerminal, paintsExactlyCountTimes(#drawParagraph, 3));
    });

    testWidgets('a run starts at its first character, after blank cells', (
      tester,
    ) async {
      final renderTerminal = await pumpTerminal(tester, '  ab  ');

      final cellWidth = renderTerminal.cellSize.width;
      final expectedOffset = Offset(2 * cellWidth, 0);

      expect(renderTerminal, paintsExactlyCountTimes(#drawParagraph, 1));
      expect(renderTerminal, paints..paragraph(offset: expectedOffset));
    });

    // A run must line up with a cell painted alone, the cursor and a
    // selection, which all sit at multiples of the cell width. Where the cell
    // width is not the font's own advance (a cell rounded to whole device
    // pixels), only the run's letter spacing keeps the characters there.
    testWidgets('each character of a run lands on its own cell', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);

      const runText = 'abcdefghij';

      final renderTerminal = await pumpTerminal(
        tester,
        runText,
        textStyle: const TerminalStyle(fontSize: 13.4),
      );

      final cellWidth = renderTerminal.cellSize.width;
      final canvas = TestRecordingCanvas();
      final context = TestRecordingPaintingContext(canvas);

      renderTerminal.paint(context, Offset.zero);

      final paragraphCalls = canvas.invocations.where(
        (call) => call.invocation.memberName == #drawParagraph,
      );
      final paragraph =
          paragraphCalls.single.invocation.positionalArguments.first
              as Paragraph;

      final firstBoxes = paragraph.getBoxesForRange(0, 1);
      final firstLeft = firstBoxes.first.left;

      expect(firstLeft.abs(), lessThanOrEqualTo(0.5));

      for (var i = 1; i < runText.length; i++) {
        final boxes = paragraph.getBoxesForRange(i, i + 1);
        final left = boxes.first.left;

        expect(
          left - firstLeft,
          closeTo(i * cellWidth, 0.01),
          reason: 'character $i is off its cell',
        );
      }
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
