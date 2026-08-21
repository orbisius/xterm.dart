import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// A drag must keep selecting while the VIEW scrolls under a held button.
///
/// The pointer stops moving once it reaches the edge of the view, so without
/// this a selection can never be longer than one screen: the far end stays on
/// the cell the pointer last touched while the content slides past it. Scrolling
/// re-resolves that same view-local position to a different cell, which is what
/// carries one selection across several pages.
void main() {
  const viewRows = 10;
  const writtenLines = 200;

  /// Enough output to scroll through, one identifiable line each.
  void writeLines(Terminal terminal) {
    for (var lineNumber = 0; lineNumber < writtenLines; lineNumber++) {
      terminal.write('line $lineNumber\r\n');
    }
  }

  /// A mounted terminal with scrollback, and the handles a drag needs.
  Future<({TerminalController controller, ScrollController scrollController})>
  pumpTerminal(WidgetTester tester) async {
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
    // TO — without it every jump below is a no-op and the assertions hold no
    // matter what the selection does.
    scrollController.jumpTo(0);

    await tester.pump();

    final handles = (
      controller: controller,
      scrollController: scrollController,
    );

    return handles;
  }

  testWidgets('scrolling with the button held keeps selecting', (tester) async {
    final handles = await pumpTerminal(tester);

    final controller = handles.controller;
    final scrollController = handles.scrollController;

    final viewCenter = tester.getCenter(find.byType(TerminalView));

    final gesture = await tester.startGesture(
      viewCenter,
      kind: PointerDeviceKind.mouse,
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    final endBeforeScroll = controller.selection?.end;

    expect(
      endBeforeScroll,
      isNotNull,
      reason: 'the drag should have started a selection',
    );

    final scrollExtent = scrollController.position.maxScrollExtent;

    // With nowhere to scroll the assertion below would hold however the
    // selection behaves, and the test would prove nothing.
    expect(
      scrollExtent,
      greaterThan(scrollController.position.pixels),
      reason: 'the view must have somewhere left to scroll to',
    );

    // Scroll WITHOUT moving the pointer and WITHOUT releasing — exactly the
    // gesture that used to stop the selection growing.
    scrollController.jumpTo(scrollExtent);

    await tester.pump();

    final endAfterScroll = controller.selection?.end;

    expect(endAfterScroll, isNotNull);
    expect(
      endAfterScroll!.y,
      greaterThan(endBeforeScroll!.y),
      reason: 'the far end must follow the content the view scrolled to',
    );

    await gesture.up();
  });

  testWidgets('scrolling after the button is up leaves the selection alone', (
    tester,
  ) async {
    // The other half of the rule: once the drag is over, scrolling is just
    // scrolling. Tracking the viewport forever would rewrite a finished
    // selection every time the user looked somewhere else.
    final handles = await pumpTerminal(tester);

    final controller = handles.controller;
    final scrollController = handles.scrollController;

    final viewCenter = tester.getCenter(find.byType(TerminalView));

    final gesture = await tester.startGesture(
      viewCenter,
      kind: PointerDeviceKind.mouse,
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    await gesture.up();
    await tester.pump();

    final endBeforeScroll = controller.selection?.end;

    expect(endBeforeScroll, isNotNull);

    final scrollExtent = scrollController.position.maxScrollExtent;

    expect(
      scrollExtent,
      greaterThan(0),
      reason: 'the view needs scrollback to scroll through',
    );

    scrollController.jumpTo(scrollExtent);

    await tester.pump();

    final endAfterScroll = controller.selection?.end;

    expect(endAfterScroll, isNotNull);
    expect(
      endAfterScroll!.y,
      endBeforeScroll!.y,
      reason: 'a finished selection must not move when the view scrolls',
    );
  });
}
