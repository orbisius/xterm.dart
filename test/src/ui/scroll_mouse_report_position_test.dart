import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// A mouse-wheel event reported to the application must name the cell the
/// pointer is actually over.
///
/// The scroll handler sits ABOVE the terminal in the widget tree, so what it
/// records is `PointerEvent.position` — a GLOBAL offset. `getCellOffset` takes
/// coordinates local to the terminal. Passing one for the other reports a cell
/// too far down and right by however far the terminal sits from the window
/// origin: a CONSTANT error, and a silent one, because nothing surfaces it
/// unless an application is reading mouse events. In a real app the terminal
/// sits under a tab strip and a toolbar, so the row is off by several lines.
///
/// This path exists only in the ALT buffer, which is where the applications that
/// read mouse events live — vim, htop, less. That is the blast radius.
void main() {
  const headerHeight = 120.0;
  const headerWidth = 60.0;
  const viewWidth = 400.0;
  const viewHeight = 300.0;

  late Terminal terminal;
  late RecordingMouseHandler mouseHandler;

  /// A terminal pushed away from the window origin on BOTH axes, the way a real
  /// app places it — below a tab strip and toolbar, right of a sidebar — and
  /// switched into the alt buffer, where the scroll path is live.
  Future<void> pumpOffsetTerminal(WidgetTester tester) async {
    terminal = Terminal(maxLines: 1000);

    mouseHandler = RecordingMouseHandler();
    terminal.mouseHandler = mouseHandler;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              const SizedBox(width: headerWidth, height: viewHeight),
              Column(
                children: [
                  const SizedBox(width: viewWidth, height: headerHeight),
                  SizedBox(
                    width: viewWidth,
                    height: viewHeight,
                    child: TerminalView(terminal),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump();

    // Into the alt screen, as a TUI does on startup.
    terminal.write('\x1b[?1049h');

    for (var lineNumber = 0; lineNumber < 12; lineNumber++) {
      terminal.write('line $lineNumber\r\n');
    }

    await tester.pump();
  }

  /// The state, for the conversion under test.
  TerminalViewState viewState(WidgetTester tester) {
    final state = tester.state<TerminalViewState>(find.byType(TerminalView));

    return state;
  }

  /// Hovers then scrolls at [globalPosition] — both events matter, because the
  /// handler records the position from the pointer signal it receives.
  Future<void> scrollAt(WidgetTester tester, Offset globalPosition) async {
    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.hover(globalPosition));

    await tester.pump();

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));

    await tester.pump();
  }

  testWidgets('reports the cell under the pointer, not one shifted by the '
      'terminal position', (tester) async {
    await pumpOffsetTerminal(tester);

    final viewTopLeft = tester.getTopLeft(find.byType(TerminalView));

    // A point inside the terminal, expressed GLOBALLY — what a real pointer
    // event carries.
    const localPoint = Offset(50, 45);

    final globalPoint = viewTopLeft + localPoint;

    await scrollAt(tester, globalPoint);

    expect(
      mouseHandler.reportedCells,
      isNotEmpty,
      reason: 'the alt-buffer scroll path should report to the application',
    );

    final reported = mouseHandler.reportedCells.last;

    final expected = viewState(tester).getCellOffsetFromGlobal(globalPoint);

    expect(reported.y, expected.y);
    expect(reported.x, expected.x);
  });

  testWidgets('the terminal offset is what the old path lost', (tester) async {
    // The bug in one assertion: treating the global point as a local one lands
    // on a different cell, so the conversion does real work rather than being a
    // no-op that happens to pass.
    await pumpOffsetTerminal(tester);

    final viewTopLeft = tester.getTopLeft(find.byType(TerminalView));

    expect(
      viewTopLeft,
      isNot(Offset.zero),
      reason: 'the harness must place the terminal away from the origin',
    );

    const localPoint = Offset(50, 45);

    final globalPoint = viewTopLeft + localPoint;

    final state = viewState(tester);

    final converted = state.getCellOffsetFromGlobal(globalPoint);

    final unconverted = state.renderTerminal.getCellOffset(globalPoint);

    expect(
      converted.y,
      lessThan(unconverted.y),
      reason: 'the old path reported a row BELOW the pointer',
    );

    expect(
      converted.x,
      lessThan(unconverted.x),
      reason: 'and a column to its right, which is why copies lost characters',
    );
  });

  testWidgets('a non-finite position yields a cell instead of throwing', (
    tester,
  ) async {
    // The conversion walks the ancestor transform, and a transform can be
    // degenerate — a display reconfigured under a running window is the case
    // that reaches it — producing NaN or infinity. getCellOffset divides with
    // `~/`, which throws on both, and the scroll handler calls this BEFORE
    // sending its report, so a throw here takes the arrow-key fallback with it
    // and the wheel stops doing anything at all.
    await pumpOffsetTerminal(tester);

    final state = viewState(tester);

    final cell = state.getCellOffsetFromGlobal(Offset.infinite);

    expect(cell.x, greaterThanOrEqualTo(0));
    expect(cell.y, greaterThanOrEqualTo(0));
  });

  testWidgets('the terminal top-left is the first visible cell', (
    tester,
  ) async {
    // The contract stated plainly: the terminal's own origin maps to whatever
    // the terminal calls its first cell, however far down the window it sits.
    await pumpOffsetTerminal(tester);

    final viewTopLeft = tester.getTopLeft(find.byType(TerminalView));

    final state = viewState(tester);

    final fromGlobal = state.getCellOffsetFromGlobal(viewTopLeft);

    final fromLocalOrigin = state.renderTerminal.getCellOffset(Offset.zero);

    expect(fromGlobal.y, fromLocalOrigin.y);
    expect(fromGlobal.x, fromLocalOrigin.x);
  });
}

/// Stands in for an application reading mouse events: records the cell it was
/// told about, and returns a report so the terminal counts the event handled.
class RecordingMouseHandler implements TerminalMouseHandler {
  final List<CellOffset> reportedCells = <CellOffset>[];

  @override
  String? call(TerminalMouseEvent event) {
    reportedCells.add(event.position);

    return '\x1b[M';
  }
}
