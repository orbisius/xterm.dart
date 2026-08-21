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

    // The terminal sticks to the bottom as it writes, so it is ALREADY at the
    // maximum offset. Starting from the top is what leaves somewhere to scroll
    // TO — jumping to the extent from the extent moves nothing, and the anchor
    // assertion below then holds with or without the fix.
    scrollController.jumpTo(0);

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
    // anchor does and the test proves nothing. Comparing against the CURRENT
    // position rather than against zero is what makes that real: the extent can
    // be large while the view already sits on it.
    expect(
      scrollExtent,
      greaterThan(scrollController.position.pixels),
      reason: 'the view must have somewhere left to scroll to',
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
    // Small enough to fill quickly; nothing below assumes a particular value.
    const maxLines = 60;

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

    // FILL the scrollback rather than guessing a line count that reaches the
    // cap. Only a full buffer evicts, and eviction is the whole subject here.
    var writtenLines = 0;

    while (terminal.buffer.lines.length < maxLines) {
      terminal.write('before $writtenLines\r\n');
      writtenLines++;

      // The loop's exit depends on buffer behaviour, so bound it: a change there
      // should fail this test, never hang the suite.
      expect(
        writtenLines,
        lessThan(maxLines * 4),
        reason: 'writing lines did not grow the buffer to its cap',
      );
    }

    await tester.pump();

    expect(
      terminal.buffer.lines.length,
      maxLines,
      reason: 'the buffer must be FULL before the drag, or nothing evicts',
    );

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

    final anchorRowBefore = anchorBefore?.y ?? 0;

    // DERIVED from where the drag actually landed: evict half the rows above the
    // anchor. Enough that every index below shifts measurably, few enough that
    // the anchor's OWN line is never among the evicted — a detached anchor would
    // test the give-up path instead of the tracking one.
    final evictionCount = anchorRowBefore ~/ 2;

    expect(
      evictionCount,
      greaterThan(0),
      reason: 'the anchor needs rows above it for the writes to evict',
    );

    // Output arrives mid-drag, exactly as it does in a live session. The buffer
    // is full, so each line written evicts exactly one and shifts every
    // surviving row's index down by one.
    for (var lineNumber = 0; lineNumber < evictionCount; lineNumber++) {
      terminal.write('during $lineNumber\r\n');
    }

    await tester.pump();

    expect(
      terminal.buffer.lines.length,
      maxLines,
      reason: 'a full buffer stays at its cap, so those writes evicted',
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    final anchorAfter = controller.selection?.begin;

    expect(anchorAfter, isNotNull);

    // The EXACT shift, not "it moved": the line the anchor holds was pushed up
    // by one per evicted line, so a tracking anchor reports precisely that. An
    // anchor that kept a stale row number would report the row it started on.
    expect(
      anchorAfter?.y,
      anchorRowBefore - evictionCount,
      reason: 'the anchor row must follow its line up as the buffer evicts',
    );

    final anchoredTextAfter = readLineText(terminal, anchorAfter);

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
