import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// A drag selection must stay anchored to the CELL it started on, not to the
/// pixel the pointer went down at.
///
/// Those two agree only while the view holds still. Scrolling mid-drag makes
/// them disagree, and an anchor recovered from the pixel then travels with the
/// viewport: the selection slides instead of growing, so one spanning more than
/// a screen cannot be dragged at all. See [RenderTerminal.selectCharactersFrom].
void main() {
  const viewRows = 10;
  const writtenLines = 200;

  /// Enough output to scroll through, one identifiable line each.
  void writeLines(Terminal terminal) {
    for (var lineNumber = 0; lineNumber < writtenLines; lineNumber++) {
      terminal.write('line $lineNumber\r\n');
    }
  }

  testWidgets('a drag keeps its anchor when the view scrolls', (tester) async {
    final terminal = Terminal(maxLines: 10000);
    final controller = TerminalController();
    final scrollController = ScrollController();

    addTearDown(scrollController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: TerminalView(
              terminal,
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
            ),
          ),
        ),
      ),
    );

    terminal.resize(80, viewRows);
    writeLines(terminal);

    await tester.pump();

    final viewCenter = tester.getCenter(find.byType(TerminalView));

    // Press and move a little, so a selection exists before anything scrolls.
    final gesture = await tester.startGesture(
      viewCenter,
      kind: PointerDeviceKind.mouse,
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    final anchorBeforeScroll = controller.selection?.begin;

    expect(
      anchorBeforeScroll,
      isNotNull,
      reason: 'the drag should have started a selection',
    );

    final scrollExtent = scrollController.position.maxScrollExtent;

    // Without somewhere to scroll, the assertion below holds no matter what the
    // anchor does and the test proves nothing.
    expect(
      scrollExtent,
      greaterThan(0),
      reason: 'the view needs scrollback to scroll through',
    );

    // Scroll WITHOUT releasing the button — the case the anchor has to survive.
    scrollController.jumpTo(scrollExtent);

    await tester.pump();

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    final anchorAfterScroll = controller.selection?.begin;

    expect(anchorAfterScroll, isNotNull);
    expect(
      anchorAfterScroll?.y,
      anchorBeforeScroll?.y,
      reason: 'the anchor row must not move with the viewport',
    );

    await gesture.up();
  });

  // The second way a start position goes stale, and the one a plain CellOffset
  // does NOT survive: a full scrollback evicts its oldest lines, which shifts
  // every row index below them. A stored index then names a different line while
  // pointing at the same number.
  testWidgets('a drag keeps its anchor when the scrollback evicts', (
    tester,
  ) async {
    // Small enough that a modest burst of output reaches the cap and starts
    // dropping lines.
    const maxLines = 60;
    const linesBeforeDrag = 50;
    const linesDuringDrag = 10;

    final terminal = Terminal(maxLines: maxLines);
    final controller = TerminalController();
    final scrollController = ScrollController();

    addTearDown(scrollController.dispose);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: TerminalView(
              terminal,
              controller: controller,
              scrollController: scrollController,
              autofocus: true,
            ),
          ),
        ),
      ),
    );

    terminal.resize(80, viewRows);

    for (var lineNumber = 0; lineNumber < linesBeforeDrag; lineNumber++) {
      terminal.write('before $lineNumber\r\n');
    }

    await tester.pump();

    final viewCenter = tester.getCenter(find.byType(TerminalView));

    final gesture = await tester.startGesture(
      viewCenter,
      kind: PointerDeviceKind.mouse,
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    final anchorBefore = controller.selection?.begin;

    expect(anchorBefore, isNotNull, reason: 'the drag should have selected');

    final anchoredTextBefore = readLineText(terminal, anchorBefore);

    expect(
      anchoredTextBefore,
      isNotEmpty,
      reason: 'the anchor should sit on a line with text on it',
    );

    final lineCountBefore = terminal.buffer.lines.length;

    // Output arrives mid-drag, exactly as it does in a live session.
    for (var lineNumber = 0; lineNumber < linesDuringDrag; lineNumber++) {
      terminal.write('during $lineNumber\r\n');
    }

    await tester.pump();

    // Without eviction the row indices never shift, and the assertion below
    // holds whether the anchor tracks its line or not.
    expect(
      terminal.buffer.lines.length,
      lineCountBefore,
      reason: 'the buffer must be AT its cap, so those writes evicted',
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    final anchorAfter = controller.selection?.begin;

    final anchoredTextAfter = readLineText(terminal, anchorAfter);

    expect(anchorAfter, isNotNull);
    expect(
      anchoredTextAfter,
      anchoredTextBefore,
      reason: 'the anchor must follow its LINE, not keep a stale row number',
    );

    await gesture.up();
  });
}

/// The text on the row [position] names, or '' when there is no position.
String readLineText(Terminal terminal, CellOffset? position) {
  if (position == null) {
    return '';
  }

  final line = terminal.buffer.lines[position.y];

  var text = line.getText();
  text = text.trimRight();

  return text;
}
