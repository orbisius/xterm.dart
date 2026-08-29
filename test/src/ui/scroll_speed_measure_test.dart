import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// How far one wheel notch travels on each screen, and that the two AGREE.
///
/// The report was that the main screen scrolls too little per notch while the
/// alternate screen jumps two or three PAGES. The two take completely different
/// paths — the main screen moves a real scroll view by pixels, the alternate
/// screen converts pixels to a COUNT of wheel reports and sends that many to the
/// program — so the first question was whether the conversion itself differed.
///
/// It does not: measured at 60px and 600px, both land within a fraction of a line
/// of each other. The felt difference comes from what CONSUMES the events — the
/// alt screen's reports are spent by the program, and most TUIs step three lines
/// per report, so the same gesture travels roughly three times as far there.
///
/// So what is pinned is the AGREEMENT at NOTCH scale, not a target speed:
/// whatever rate is chosen, a change that moves one path without the other at
/// that scale is a bug. The measured numbers are printed with it, because the
/// ratio is the thing being tuned.
///
/// ACCELERATED spins are the deliberate exception (see `scroll_bounded_test`):
/// the alt path CAPS what one event may send
/// ([TerminalScrollGestureHandler.maxLinesPerScrollEvent]) and takes no
/// ballistic coast, while the main screen keeps both. The two differ on
/// purpose — alt events are executed by a program with no way back, the main
/// screen is a local view a scrollbar can recover.
void main() {
  const viewWidth = 400.0;
  const viewHeight = 300.0;

  /// One notch as the framework delivers it. macOS reports accelerated deltas,
  /// so a fast spin sends much more than this in a single event.
  const oneNotchPixels = 60.0;

  late Terminal terminal;
  late RecordingMouseHandler mouseHandler;
  late ScrollController scrollController;

  Future<void> pumpTerminal(WidgetTester tester) async {
    terminal = Terminal(maxLines: 1000);

    mouseHandler = RecordingMouseHandler();
    terminal.mouseHandler = mouseHandler;

    // Supplied rather than left to the view, so the MAIN screen's travel can be
    // read in pixels — that screen scrolls a real scroll view, not the buffer.
    scrollController = ScrollController();

    addTearDown(scrollController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: viewWidth,
            height: viewHeight,
            child: TerminalView(terminal, scrollController: scrollController),
          ),
        ),
      ),
    );

    await tester.pump();
  }

  /// The pixel height of one line, from the render object that owns the grid.
  double readLineHeight(WidgetTester tester) {
    final state = tester.state<TerminalViewState>(find.byType(TerminalView));

    final lineHeight = state.renderTerminal.cellSize.height;

    return lineHeight;
  }

  /// Fills the MAIN screen with enough history to scroll through.
  void writeScrollback() {
    for (var lineNumber = 0; lineNumber < 200; lineNumber++) {
      terminal.write('line $lineNumber\r\n');
    }
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

  testWidgets('MEASURE: alternate screen — reports sent per wheel notch', (
    tester,
  ) async {
    await pumpTerminal(tester);

    enterAltScreen();

    await tester.pump();

    final viewHeightInLines = terminal.viewHeight;

    mouseHandler.reportedCells.clear();

    await scrollBy(tester, oneNotchPixels);

    final reportCount = mouseHandler.reportedCells.length;

    final pagesPerNotch = reportCount / viewHeightInLines;

    debugPrint(
      'ALT: $oneNotchPixels px notch -> $reportCount wheel reports; '
      'view is $viewHeightInLines lines -> '
      '${pagesPerNotch.toStringAsFixed(2)} pages per notch',
    );

    // A notch must move roughly the pixels it carries, converted at the line
    // height — not a page, and not nothing. Bounds rather than an exact count,
    // because the conversion floors and the cell height depends on the font.
    final expectedLines = oneNotchPixels / readLineHeight(tester);

    expect(reportCount, greaterThan(0));
    expect(reportCount, lessThanOrEqualTo(expectedLines.ceil()));
    expect(reportCount, greaterThanOrEqualTo(expectedLines.floor() - 1));

    // The guard that stops this reading as "a notch scrolls a page": the view
    // must be several notches tall, or the two would be indistinguishable.
    expect(pagesPerNotch, lessThan(0.5));
  });

  testWidgets('MEASURE: alternate screen — a fast, accelerated spin', (
    tester,
  ) async {
    // What macOS actually delivers when the wheel is spun quickly: one event
    // carrying a much larger delta, not many small ones.
    await pumpTerminal(tester);

    enterAltScreen();

    await tester.pump();

    mouseHandler.reportedCells.clear();

    await scrollBy(tester, 600);

    final reportCount = mouseHandler.reportedCells.length;

    final pagesPerNotch = reportCount / terminal.viewHeight;

    debugPrint(
      'ALT: 600 px flick -> $reportCount wheel reports; '
      '${pagesPerNotch.toStringAsFixed(2)} pages',
    );

    expect(reportCount, greaterThan(0));
  });

  testWidgets('MEASURE: main screen — lines moved per wheel notch', (
    tester,
  ) async {
    await pumpTerminal(tester);

    writeScrollback();

    await tester.pump();

    final lineHeight = readLineHeight(tester);

    final offsetBefore = scrollController.offset;

    await scrollBy(tester, -oneNotchPixels);

    final offsetAfter = scrollController.offset;

    final pixelsMoved = offsetAfter - offsetBefore;
    final linesMoved = pixelsMoved / lineHeight;

    final pagesPerNotch = linesMoved / terminal.viewHeight;

    debugPrint(
      'MAIN: $oneNotchPixels px notch -> ${pixelsMoved.toStringAsFixed(1)} px '
      '= ${linesMoved.toStringAsFixed(2)} lines '
      '(line height ${lineHeight.toStringAsFixed(2)} px); '
      'view is ${terminal.viewHeight} lines -> '
      '${pagesPerNotch.toStringAsFixed(2)} pages per notch',
    );

    expect(offsetAfter, isNot(offsetBefore));
  });

  testWidgets('MEASURE: main screen — the same fast spin', (tester) async {
    await pumpTerminal(tester);

    writeScrollback();

    await tester.pump();

    final lineHeight = readLineHeight(tester);

    final offsetBefore = scrollController.offset;

    await scrollBy(tester, -600);

    final offsetAfter = scrollController.offset;

    final linesMoved = (offsetAfter - offsetBefore) / lineHeight;

    debugPrint(
      'MAIN: 600 px flick -> ${linesMoved.toStringAsFixed(2)} lines; '
      '${(linesMoved / terminal.viewHeight).toStringAsFixed(2)} pages',
    );

    expect(offsetAfter, isNot(offsetBefore));
  });

  testWidgets('the two screens convert the same gesture to the same travel', (
    tester,
  ) async {
    // THE regression guard. The tests above measure each path alone, and alone
    // they could drift apart without either failing. This one puts the same
    // delta through both in a single widget and requires them to agree, so a
    // change that speeds up or slows down ONE screen cannot pass.
    // Each on a FRESH mount. Switching buffers under a scrolled main view leaves
    // that view claiming the pointer signal, so the alt path never sees it — a
    // property of the harness, not of the code under test.
    await pumpTerminal(tester);

    writeScrollback();

    await tester.pump();

    final lineHeight = readLineHeight(tester);

    final mainOffsetBefore = scrollController.offset;

    await scrollBy(tester, -oneNotchPixels);

    final mainPixelsMoved = scrollController.offset - mainOffsetBefore;
    final mainLines = mainPixelsMoved.abs() / lineHeight;

    await pumpTerminal(tester);

    enterAltScreen();

    await tester.pump();

    mouseHandler.reportedCells.clear();

    await scrollBy(tester, oneNotchPixels);

    final altLines = mouseHandler.reportedCells.length.toDouble();

    debugPrint(
      'AGREEMENT: main ${mainLines.toStringAsFixed(2)} lines vs '
      'alt ${altLines.toStringAsFixed(2)} reports for the same '
      '$oneNotchPixels px',
    );

    // Both must actually have moved, or "they agree" would be two zeros.
    expect(mainLines, greaterThan(0));
    expect(altLines, greaterThan(0));

    // Within one line: the alt path counts whole reports while the main path
    // moves fractional pixels, so they cannot land on exactly the same number.
    final difference = (mainLines - altLines).abs();

    expect(difference, lessThan(1.0));
  });
}

class RecordingMouseHandler implements TerminalMouseHandler {
  final List<CellOffset> reportedCells = <CellOffset>[];

  @override
  String? call(TerminalMouseEvent event) {
    reportedCells.add(event.position);

    return '\x1b[M';
  }
}
