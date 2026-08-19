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
}
