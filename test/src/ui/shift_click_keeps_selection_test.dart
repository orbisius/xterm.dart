import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// SHIFT+click means "extend the selection to here", so the selection has to
/// survive the tap that extends it.
///
/// Tap-down clears the selection, which is right for a plain click and wrong for
/// a modified one: the extend then has nothing left to extend FROM, and anything
/// that rebuilds it does so a frame later, which reads as the selection blinking
/// out and coming back.
void main() {
  const viewRows = 10;
  const writtenLines = 40;

  /// A mounted terminal with a few identifiable lines, and its controller.
  Future<TerminalController> pumpTerminal(WidgetTester tester) async {
    final terminal = Terminal(maxLines: 1000);
    final controller = TerminalController();

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 200,
            child: TerminalView(terminal, controller: controller, autofocus: true),
          ),
        ),
      ),
    );

    terminal.resize(80, viewRows);

    for (var lineNumber = 0; lineNumber < writtenLines; lineNumber++) {
      terminal.write('line $lineNumber\r\n');
    }

    await tester.pump();

    return controller;
  }

  /// Drags a short distance so a selection exists to be extended.
  Future<void> dragOutASelection(WidgetTester tester) async {
    final viewCenter = tester.getCenter(find.byType(TerminalView));

    final gesture = await tester.startGesture(
      viewCenter,
      kind: PointerDeviceKind.mouse,
    );

    await gesture.moveBy(const Offset(40, 0));
    await tester.pump();

    await gesture.up();
    await tester.pump();
  }

  testWidgets('SHIFT+click keeps the selection it is extending', (tester) async {
    final controller = await pumpTerminal(tester);

    await dragOutASelection(tester);

    // Without a selection to begin with there is nothing for tap-down to clear,
    // so the assertion below would hold however the handler behaved.
    expect(
      controller.selection,
      isNotNull,
      reason: 'the drag should have left a selection to extend',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

    final viewCenter = tester.getCenter(find.byType(TerminalView));

    await tester.tapAt(viewCenter + const Offset(60, 20));

    // Tap-up arms a double-tap timer; letting it expire keeps the test from
    // ending with one still pending, which the framework treats as a failure.
    await tester.pump(kDoubleTapTimeout);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    expect(
      controller.selection,
      isNotNull,
      reason: 'a shift-click must not clear what it is extending',
    );
  });

  testWidgets('a plain click still clears the selection', (tester) async {
    // The other half of the rule. Keeping a selection through every tap would
    // leave no way to dismiss one.
    final controller = await pumpTerminal(tester);

    await dragOutASelection(tester);

    expect(controller.selection, isNotNull);

    final viewCenter = tester.getCenter(find.byType(TerminalView));

    await tester.tapAt(viewCenter + const Offset(60, 20));

    await tester.pump(kDoubleTapTimeout);

    expect(
      controller.selection,
      isNull,
      reason: 'an unmodified click still dismisses the selection',
    );
  });
}
