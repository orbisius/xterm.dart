import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/mouse/handler.dart';
import 'package:xterm/xterm.dart';

/// PINS that the alternate-screen wheel keeps reaching the program after the
/// enclosing Scrollable swaps its ViewportOffset.
///
/// A Scrollable disposes its position and builds a new one whenever its
/// dependencies change — a devicePixelRatio change is one such dependency, and
/// a display being reconnected delivers exactly that. Nothing about the swap is
/// visible: the old position is disposed, so a listener stranded on it raises
/// nothing, the offset still moves, and no scroll is ever reported again.
///
/// The reported symptom was a wheel that stopped working until the pane was
/// dragged out of the tab strip and back, which remounts the subtree — the one
/// thing that re-registers the listener.
void main() {
  const viewWidth = 400.0;
  const viewHeight = 300.0;

  /// One notch as the framework delivers it.
  const oneNotchPixels = 60.0;

  late Terminal terminal;
  late _RecordingMouseHandler mouseHandler;

  Future<void> pumpTerminal({
    required WidgetTester tester,
    required double devicePixelRatio,
  }) async {
    final mediaQueryData = MediaQueryData(devicePixelRatio: devicePixelRatio);

    await tester.pumpWidget(
      MediaQuery(
        data: mediaQueryData,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: viewWidth,
              height: viewHeight,
              child: TerminalView(terminal),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
  }

  /// Switches to the alternate screen and paints it, as a full-screen program
  /// does.
  void enterAltScreen() {
    terminal.write('\x1b[?1049h');

    for (var lineNumber = 0; lineNumber < 12; lineNumber++) {
      terminal.write('alt $lineNumber\r\n');
    }
  }

  Future<void> scrollOneNotch(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(TerminalView));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.hover(center));
    await tester.pump();

    await tester.sendEventToBinding(pointer.scroll(const Offset(0, oneNotchPixels)));
    await tester.pump();
  }

  /// How many scroll events the program received from one notch.
  Future<int> countReportsForOneNotch(WidgetTester tester) async {
    mouseHandler.events.clear();

    await scrollOneNotch(tester);

    final reportCount = mouseHandler.events.length;

    return reportCount;
  }

  setUp(() {
    terminal = Terminal(maxLines: 1000);

    mouseHandler = _RecordingMouseHandler();
    terminal.mouseHandler = mouseHandler;
  });

  testWidgets('the wheel still reaches the program after a dpr change', (
    tester,
  ) async {
    await pumpTerminal(tester: tester, devicePixelRatio: 1);

    enterAltScreen();

    await tester.pump();

    final beforeCount = await countReportsForOneNotch(tester);

    expect(
      beforeCount,
      greaterThan(0),
      reason: 'the fixture never reported a scroll to begin with',
    );

    // The display change: a new devicePixelRatio makes the Scrollable rebuild
    // its position, disposing the one every listener was registered on.
    await pumpTerminal(tester: tester, devicePixelRatio: 2);

    final afterCount = await countReportsForOneNotch(tester);

    expect(
      afterCount,
      greaterThan(0),
      reason: 'the wheel stopped reaching the program after the position swap',
    );
  });

  testWidgets('a position swap does not need a remount to recover', (
    tester,
  ) async {
    await pumpTerminal(tester: tester, devicePixelRatio: 1);

    enterAltScreen();

    await tester.pump();

    await pumpTerminal(tester: tester, devicePixelRatio: 3);
    await pumpTerminal(tester: tester, devicePixelRatio: 1);

    final afterCount = await countReportsForOneNotch(tester);

    expect(
      afterCount,
      greaterThan(0),
      reason: 'repeated swaps left the wheel permanently detached',
    );
  });
}

class _RecordingMouseHandler implements TerminalMouseHandler {
  final List<TerminalMouseEvent> events = [];

  @override
  String? call(TerminalMouseEvent event) {
    events.add(event);

    // A report string, so the terminal treats the event as handled and never
    // falls back to arrow keys — every scroll line lands in [events].
    return '';
  }
}
