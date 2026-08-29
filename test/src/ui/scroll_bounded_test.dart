import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/core/mouse/handler.dart';
import 'package:xterm/src/ui/scroll_handler.dart';
import 'package:xterm/xterm.dart';

/// Alt-screen scrolling is BOUNDED: an accelerated wheel event may not turn
/// into pages of reports, and a fling coasts nothing after the fingers lift.
///
/// macOS delivers a fast spin as ONE event carrying hundreds of pixels;
/// unbounded, a 600 px event became 37 reports — about two pages — executed
/// by the program with nothing to take it back. And with no scroll physics,
/// a trackpad fling ran the platform's ballistic simulation on an INFINITE
/// extent, where it never meets a boundary — every line it coasted through
/// after the fingers lifted fired another report.
void main() {
  const viewWidth = 400.0;
  const viewHeight = 300.0;

  /// One notch as the framework delivers it.
  const oneNotchPixels = 60.0;

  late Terminal terminal;
  late _RecordingMouseHandler mouseHandler;

  Future<void> pumpTerminal(WidgetTester tester) async {
    terminal = Terminal(maxLines: 1000);

    mouseHandler = _RecordingMouseHandler();
    terminal.mouseHandler = mouseHandler;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: viewWidth,
            height: viewHeight,
            child: TerminalView(terminal),
          ),
        ),
      ),
    );

    await tester.pump();
  }

  /// The pixel height of one line, from the render object that owns the grid.
  double readLineHeight(WidgetTester tester) {
    final state = tester.state<TerminalViewState>(find.byType(TerminalView));

    final lineHeight = state.renderTerminal.lineHeight;

    return lineHeight;
  }

  /// Switches to the alternate screen and paints it, as a TUI does.
  void enterAltScreen() {
    terminal.write('\x1b[?1049h');

    for (var lineNumber = 0; lineNumber < 12; lineNumber++) {
      terminal.write('alt $lineNumber\r\n');
    }
  }

  Future<void> scrollBy(WidgetTester tester, double pixels) async {
    final center = tester.getCenter(find.byType(TerminalView));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.hover(center));
    await tester.pump();

    await tester.sendEventToBinding(pointer.scroll(Offset(0, pixels)));
    await tester.pump();
  }

  testWidgets('a plain notch still scrolls', (tester) async {
    await pumpTerminal(tester);

    enterAltScreen();

    await tester.pump();

    mouseHandler.events.clear();

    await scrollBy(tester, oneNotchPixels);

    final reportCount = mouseHandler.events.length;

    expect(reportCount, greaterThan(0));
    expect(
      reportCount,
      lessThanOrEqualTo(TerminalScrollGestureHandler.maxLinesPerScrollEvent),
    );
  });

  testWidgets('an accelerated event is capped, never pages of travel', (
    tester,
  ) async {
    // What macOS actually delivers when the wheel is spun quickly: one event
    // carrying a much larger delta, not many small ones.
    await pumpTerminal(tester);

    enterAltScreen();

    await tester.pump();

    mouseHandler.events.clear();

    await scrollBy(tester, 600);

    final reportCount = mouseHandler.events.length;

    expect(reportCount, greaterThan(0));
    expect(
      reportCount,
      lessThanOrEqualTo(TerminalScrollGestureHandler.maxLinesPerScrollEvent),
    );
  });

  testWidgets('a fling coasts nothing after the fingers lift', (tester) async {
    await pumpTerminal(tester);

    enterAltScreen();

    await tester.pump();

    mouseHandler.events.clear();

    const flingPixels = 240.0;

    await tester.fling(
      find.byType(TerminalView),
      const Offset(0, -flingPixels),
      2000,
    );

    // Let any ballistic simulation play out — with no-ballistic physics there
    // is none.
    await tester.pumpAndSettle();

    final reportCount = mouseHandler.events.length;

    final draggedLines = flingPixels / readLineHeight(tester);

    expect(reportCount, greaterThan(0));

    // The gesture may deliver what the FINGERS travelled — never a coast on
    // top of it. One line of slack for the flooring at event boundaries.
    expect(reportCount, lessThanOrEqualTo(draggedLines.ceil() + 1));
  });
}

/// Counts every mouse event the program would have received.
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
