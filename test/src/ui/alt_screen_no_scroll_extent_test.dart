import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// PINS that the alternate screen's viewport reports NO scroll extent, and that
/// the main screen's still does.
///
/// Two nested scrollables compete for one wheel notch and the INNER one is
/// offered it first, declining only while it has nowhere to go. Any extent at
/// all makes it accept instead, and the running program stops receiving the
/// wheel — scrolling that appears dead until the pane happens to relayout.
///
/// The terminal is given more rows than the box can show, with autoResize off
/// so nothing corrects the mismatch. That is precisely the state in which the
/// extent is otherwise non-zero, and it stands in for the same condition
/// reached by an extent left over from an earlier layout.
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

  testWidgets('the alternate screen viewport cannot scroll', (tester) async {
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
      0.0,
      reason: 'a scrollable alt viewport takes the wheel from the program',
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
