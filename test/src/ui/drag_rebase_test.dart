import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// A live drag must extend from the CONTROLLER's selection base, so an
/// embedder can RE-BASE the selection mid-drag and have it hold.
///
/// On the alternate screen a program scrolls by repainting cells IN PLACE, so
/// the drag's line-bound anchor stays on a row whose text has moved away; only
/// the embedder knows how far the content shifted, and it says so by
/// re-issuing [TerminalController.setSelection] with shifted anchors. Without
/// this, the very next pointer move re-asserted the selection from the stale
/// anchor and stomped the re-base. See [RenderTerminal] and
/// [TerminalController.selectionBaseAnchor].
void main() {
  const viewRows = 10;
  const writtenLines = 8;

  /// How far the simulated embedder re-bases the drag — a couple of rows, the
  /// shape of a small program scroll.
  const rebaseRowShift = 2;

  void writeLines(Terminal terminal) {
    for (var lineNumber = 0; lineNumber < writtenLines; lineNumber++) {
      terminal.write('line $lineNumber\r\n');
    }
  }

  Future<TerminalController> pumpTerminal(
    WidgetTester tester,
    Terminal terminal,
  ) async {
    final controller = TerminalController();

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
              autofocus: true,
            ),
          ),
        ),
      ),
    );

    terminal.resize(80, viewRows);
    writeLines(terminal);

    await tester.pump();

    return controller;
  }

  testWidgets('an embedder re-base mid-drag HOLDS through the next update', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 1000);
    final controller = await pumpTerminal(tester, terminal);

    final viewCenter = tester.getCenter(find.byType(TerminalView));

    final gesture = await tester.startGesture(
      viewCenter,
      kind: PointerDeviceKind.mouse,
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    final beginBeforeRebase = controller.selection?.begin;
    final endBeforeRebase = controller.selection?.end;

    expect(
      beginBeforeRebase,
      isNotNull,
      reason: 'the drag should have started a selection',
    );

    // The press must land low enough that a re-base UP stays in the buffer —
    // without this the shifted row could clamp and the discriminator vanish.
    expect(
      beginBeforeRebase!.y,
      greaterThanOrEqualTo(rebaseRowShift),
      reason: 'the fixture must leave room to re-base upward',
    );

    // The embedder speaks: the content moved up, so the selection's base is
    // now this many rows higher — what an alt-screen tracker paints after a
    // voted shift.
    final rebasedRow = beginBeforeRebase.y - rebaseRowShift;

    final rebasedBase = terminal.buffer.createAnchor(
      beginBeforeRebase.x,
      rebasedRow,
    );
    final rebasedExtent = terminal.buffer.createAnchor(
      endBeforeRebase!.x,
      endBeforeRebase.y - rebaseRowShift,
    );

    controller.setSelection(rebasedBase, rebasedExtent);

    await tester.pump();

    // Precondition, so the assertion below cannot pass vacuously: the re-base
    // really landed, on a row that DIFFERS from the drag's own anchor row.
    expect(controller.selection?.begin.y, rebasedRow);
    expect(rebasedRow, isNot(beginBeforeRebase.y));

    // The pointer moves again — the moment the stale anchor used to stomp the
    // re-base.
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();

    expect(
      controller.selection?.begin.y,
      rebasedRow,
      reason: 'the drag must continue from the re-based row, '
          'not snap back to the press row',
    );

    await gesture.up();
  });

  testWidgets('a stock drag still grows from its own press cell', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 1000);
    final controller = await pumpTerminal(tester, terminal);

    final viewCenter = tester.getCenter(find.byType(TerminalView));

    final gesture = await tester.startGesture(
      viewCenter,
      kind: PointerDeviceKind.mouse,
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    final beginAfterFirstMove = controller.selection?.begin;

    expect(beginAfterFirstMove, isNotNull);

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    expect(
      controller.selection?.begin,
      beginAfterFirstMove,
      reason: 'with no re-base the drag keeps its own start',
    );

    await gesture.up();
  });

  testWidgets('a CLEARED selection falls back to the drag anchor', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 1000);
    final controller = await pumpTerminal(tester, terminal);

    final viewCenter = tester.getCenter(find.byType(TerminalView));

    final gesture = await tester.startGesture(
      viewCenter,
      kind: PointerDeviceKind.mouse,
    );

    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();

    final beginBeforeClear = controller.selection?.begin;

    expect(beginBeforeClear, isNotNull);

    controller.clearSelection();

    await tester.pump();

    expect(controller.selection, isNull);

    // The next update re-selects from the drag's own anchor — the stock
    // recovery, unchanged.
    await gesture.moveBy(const Offset(10, 0));
    await tester.pump();

    expect(controller.selection?.begin, beginBeforeClear);

    await gesture.up();
  });

  testWidgets('selectionBaseAnchor is the base AS PASSED, even reversed', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 1000);
    final controller = await pumpTerminal(tester, terminal);

    // A reversed selection: the base BELOW the extent, the shape an upward
    // drag produces.
    final base = terminal.buffer.createAnchor(5, 4);
    final extent = terminal.buffer.createAnchor(2, 1);

    controller.setSelection(base, extent);

    expect(controller.selectionBaseAnchor?.offset.y, 4);
    expect(controller.selectionBaseAnchor?.offset.x, 5);

    controller.clearSelection();

    expect(controller.selectionBaseAnchor, isNull);
  });
}
