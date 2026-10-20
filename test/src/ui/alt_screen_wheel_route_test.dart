import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

const viewWidth = 400.0;

const viewHeight = 300.0;

/// One notch as the framework delivers it; negative scrolls UP.
const oneNotchUpPixels = -60.0;

const altScreenOn = '\x1b[?1049h';

/// Mouse reporting with SGR coordinates — what a program sends to get the
/// wheel and the clicks.
const mouseReportingOn = '\x1b[?1000h\x1b[?1006h';

/// DECSET 1007: wheel turns become arrow keys, the program's other way to ask.
const alternateScrollOn = '\x1b[?1007h';

/// SGR wheel-up report prefix (button 64).
const wheelUpReportPrefix = '\x1b[<64;';

const arrowUp = '\x1b[A';

/// A terminal in a fixed-size box, with everything it sends to the program
/// collected in [programInput].
class WheelFixture {
  WheelFixture() {
    terminal.onOutput = programInput.add;
  }

  final terminal = Terminal(maxLines: 1000);

  final scrollController = ScrollController();

  final programInput = <String>[];

  Future<void> pump({
    required WidgetTester tester,
    AltScreenWheelFallback wheelFallback = AltScreenWheelFallback.scrollHistory,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: viewWidth,
            height: viewHeight,
            child: TerminalView(
              terminal,
              scrollController: scrollController,
              altScreenWheelFallback: wheelFallback,
            ),
          ),
        ),
      ),
    );

    await tester.pump();
  }

  /// Enters the alternate screen and streams [lineCount] lines on it, so the
  /// buffer keeps history above the screen.
  Future<void> streamOnAltScreen({
    required WidgetTester tester,
    String modes = '',
    int lineCount = 100,
  }) async {
    terminal.write('$altScreenOn$modes');

    for (var number = 0; number < lineCount; number++) {
      terminal.write('program line $number\r\n');
    }

    await tester.pump();
  }

  Future<void> scrollUpOneNotch(WidgetTester tester) async {
    final center = tester.getCenter(find.byType(TerminalView));

    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    await tester.sendEventToBinding(pointer.hover(center));
    await tester.pump();

    await tester.sendEventToBinding(
      pointer.scroll(const Offset(0, oneNotchUpPixels)),
    );
    await tester.pump();
  }

  bool get isAtNewestLine {
    final position = scrollController.position;
    final isAtBottom = position.pixels >= position.maxScrollExtent;

    return isAtBottom;
  }

  /// The precondition every "the view stays" assertion needs: with no extent
  /// the view is at its newest line whatever happens, and proves nothing.
  void expectHistoryToScroll() {
    final extent = scrollController.position.maxScrollExtent;

    expect(extent, greaterThan(0), reason: 'the kept lines give it a range');
  }

  bool get sentAnyWheelReport {
    final reported = programInput.any(isWheelUpReport);

    return reported;
  }

  bool get sentAnyArrowUp {
    final sent = programInput.contains(arrowUp);

    return sent;
  }
}

bool isWheelUpReport(String input) {
  final isReport = input.startsWith(wheelUpReportPrefix);

  return isReport;
}

/// PINS who gets the wheel on the alternate screen now that it keeps history:
/// the program when it asked for the wheel, the kept history otherwise —
/// owner decision A, 2026-09-05.
void main() {
  testWidgets('a program that did not ask: the wheel scrolls the history', (
    tester,
  ) async {
    final fixture = WheelFixture();

    await fixture.pump(tester: tester);
    await fixture.streamOnAltScreen(tester: tester);

    fixture.expectHistoryToScroll();

    expect(fixture.isAtNewestLine, isTrue, reason: 'it opens on the newest');

    await fixture.scrollUpOneNotch(tester);

    expect(fixture.isAtNewestLine, isFalse, reason: 'the view moved up');
    expect(fixture.sentAnyArrowUp, isFalse);
    expect(fixture.sentAnyWheelReport, isFalse);
  });

  testWidgets('a program that asked for the wheel gets it; the view stays', (
    tester,
  ) async {
    final fixture = WheelFixture();

    await fixture.pump(tester: tester);
    await fixture.streamOnAltScreen(tester: tester, modes: mouseReportingOn);

    fixture.expectHistoryToScroll();

    await fixture.scrollUpOneNotch(tester);

    expect(fixture.sentAnyWheelReport, isTrue);
    expect(fixture.isAtNewestLine, isTrue, reason: 'the program owns it');
  });

  testWidgets('mode 1007 turns the wheel into arrow keys', (tester) async {
    final fixture = WheelFixture();

    await fixture.pump(tester: tester);
    await fixture.streamOnAltScreen(tester: tester, modes: alternateScrollOn);

    fixture.expectHistoryToScroll();

    await fixture.scrollUpOneNotch(tester);

    expect(fixture.sentAnyArrowUp, isTrue);
    expect(fixture.isAtNewestLine, isTrue);
  });

  testWidgets('the sendToProgram fallback keeps the arrows of before', (
    tester,
  ) async {
    final fixture = WheelFixture();

    await fixture.pump(
      tester: tester,
      wheelFallback: AltScreenWheelFallback.sendToProgram,
    );
    await fixture.streamOnAltScreen(tester: tester);

    fixture.expectHistoryToScroll();

    await fixture.scrollUpOneNotch(tester);

    expect(fixture.sentAnyArrowUp, isTrue);
    expect(fixture.isAtNewestLine, isTrue);
  });

  testWidgets('entering the program opens on its newest line', (tester) async {
    final fixture = WheelFixture();

    await fixture.pump(tester: tester);

    // The shell's history, scrolled up — the state a program starts from.
    for (var number = 0; number < 200; number++) {
      fixture.terminal.write('shell line $number\r\n');
    }

    await tester.pump();

    fixture.scrollController.jumpTo(0);

    await tester.pump();

    expect(fixture.isAtNewestLine, isFalse, reason: 'the fixture scrolled up');

    await fixture.streamOnAltScreen(tester: tester);

    fixture.expectHistoryToScroll();

    expect(fixture.isAtNewestLine, isTrue);

    fixture.terminal.write('one more line\r\n');

    await tester.pump();

    expect(fixture.isAtNewestLine, isTrue, reason: 'new output is followed');
  });

  testWidgets('a click reports the SCREEN row, not the row in history', (
    tester,
  ) async {
    final fixture = WheelFixture();

    await fixture.pump(tester: tester);
    await fixture.streamOnAltScreen(tester: tester, modes: mouseReportingOn);

    expect(
      fixture.terminal.buffer.scrollBack,
      greaterThan(0),
      reason: 'the history the row must not be counted in',
    );

    // Only at the newest line does a screen row differ from its buffer row.
    fixture.expectHistoryToScroll();

    expect(fixture.isAtNewestLine, isTrue);

    final viewFinder = find.byType(TerminalView);
    final viewState = tester.state<TerminalViewState>(viewFinder);
    final renderTerminal = viewState.renderTerminal;
    final lineHeight = renderTerminal.lineHeight;

    // The middle of screen row 2 (reported as 3), found where the view really
    // draws it: pinned to the newest line, the view shows a sliver of the last
    // kept row above the screen, so row 0 is not at the top edge.
    final screenRowTwo = CellOffset(
      0,
      fixture.terminal.buffer.scrollBack + 2,
    );
    final rowTopLeft = renderTerminal.getOffset(screenRowTwo);
    final rowMiddle = rowTopLeft + Offset(5, lineHeight / 2);
    final clickPosition = renderTerminal.localToGlobal(rowMiddle);

    fixture.programInput.clear();

    await tester.tapAt(clickPosition);

    // Lets the double-tap recognizer give up on a second tap.
    await tester.pump(kDoubleTapTimeout);

    final pressReport = fixture.programInput.firstWhere(isPressReport);

    expect(pressReport, endsWith(';3M'));
  });
}

/// An SGR left-button press report: `ESC [ < 0 ; col ; row M`.
bool isPressReport(String input) {
  final isPress = input.startsWith('\x1b[<0;') && input.endsWith('M');

  return isPress;
}
