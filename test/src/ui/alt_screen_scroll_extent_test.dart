import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// PINS that both screens report the scroll extent their rows need.
///
/// The alternate screen used to report none, because a zero extent was what
/// kept the wheel for the program. It keeps history now, so the extent is
/// real, and a program that asks for the wheel keeps it by the handler's own
/// routing — `alt_screen_wheel_route_test.dart`.
///
/// The terminal is given more rows than the box can show, with autoResize off
/// so nothing corrects the mismatch.
void main() {
  const viewWidth = 400.0;
  const viewHeight = 300.0;

  const altScreenOn = '\x1b[?1049h';

  /// Rows far beyond what [viewHeight] can show, so the terminal's own height
  /// and the box disagree.
  const terminalColumns = 80;
  const terminalRows = 200;

  Future<ScrollController> pumpOversizedTerminal({
    required WidgetTester tester,
    required Terminal terminal,
  }) async {
    final scrollController = ScrollController();

    terminal.resize(terminalColumns, terminalRows);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: viewWidth,
            height: viewHeight,
            child: TerminalView(
              terminal,
              scrollController: scrollController,
              autoResize: false,
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    return scrollController;
  }

  testWidgets('the alternate screen viewport scrolls like the main one', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 1000);

    final scrollController = await pumpOversizedTerminal(
      tester: tester,
      terminal: terminal,
    );

    terminal.write(altScreenOn);

    await tester.pump();

    expect(terminal.isUsingAltBuffer, isTrue);

    expect(
      scrollController.position.maxScrollExtent,
      greaterThan(0.0),
      reason: 'rows beyond the box give the alternate screen an extent too',
    );
  });

  testWidgets('the main screen viewport still scrolls', (tester) async {
    final terminal = Terminal(maxLines: 1000);

    final scrollController = await pumpOversizedTerminal(
      tester: tester,
      terminal: terminal,
    );

    expect(terminal.isUsingAltBuffer, isFalse);

    expect(
      scrollController.position.maxScrollExtent,
      greaterThan(0.0),
      reason: 'the guard must be alt-screen only, not a blanket zero',
    );
  });
}
