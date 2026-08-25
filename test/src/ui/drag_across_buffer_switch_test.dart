import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

/// A drag held while a program switches screens must not crash the app.
///
/// The drag remembers where it started as an ANCHOR, and an anchor holds its
/// LINE — which outlives the switch that hides it. A drag begun deep in the main
/// screen's scrollback therefore keeps reporting a row that the short alternate
/// screen does not have, and building an anchor from it indexes past the end.
///
/// Reachable in ordinary use: hold a selection, and the command running
/// underneath opens a full-screen program. Under heavy output the scroll ticks
/// re-run the drag continuously, so the window for it is wide.
void main() {
  const viewRows = 10;
  const scrollbackLines = 400;

  late Terminal terminal;
  late TerminalController controller;

  /// A terminal with a deep MAIN-screen scrollback, mounted.
  Future<void> pumpDeepScrollback(WidgetTester tester) async {
    terminal = Terminal(maxLines: 1000);
    controller = TerminalController();

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 300,
            child: TerminalView(terminal, controller: controller),
          ),
        ),
      ),
    );

    terminal.resize(80, viewRows);

    for (var line = 0; line < scrollbackLines; line++) {
      terminal.write('main line $line\r\n');
    }

    await tester.pump();
  }

  /// The render object driving the selection.
  RenderTerminal readRenderTerminal(WidgetTester tester) {
    final state = tester.state<TerminalViewState>(find.byType(TerminalView));

    return state.renderTerminal;
  }

  testWidgets('a drag anchored deep in the scrollback survives the alt screen', (
    tester,
  ) async {
    await pumpDeepScrollback(tester);

    final render = readRenderTerminal(tester);

    // Anchored on a row far beyond anything the alt screen will have.
    final deepAnchor = terminal.buffer.createAnchor(0, 300);

    render.selectCharactersFrom(deepAnchor, const Offset(50, 40));

    expect(controller.selection, isNotNull);

    // The program takes the screen while the button is still down.
    terminal.write('\x1b[?1049h');

    await tester.pump();

    expect(terminal.buffer.lines.length, lessThan(300));

    // Re-running the drag must not throw — this is the crash.
    render.selectCharactersFrom(deepAnchor, const Offset(60, 50));

    await tester.pump();
  });

  testWidgets('scrolling during the switch does not throw either', (
    tester,
  ) async {
    // The same anchor, reached through the scroll path rather than a pointer
    // move — that is the one that re-runs on its own while output arrives.
    await pumpDeepScrollback(tester);

    final render = readRenderTerminal(tester);

    final deepAnchor = terminal.buffer.createAnchor(0, 300);

    render.selectCharactersFrom(deepAnchor, const Offset(50, 40));

    terminal.write('\x1b[?1049h');

    await tester.pump();

    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    final viewCentre = tester.getCenter(find.byType(TerminalView));

    await tester.sendEventToBinding(pointer.hover(viewCentre));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 80)));

    await tester.pump();
  });

  testWidgets('a drag anchored on the CURRENT screen still selects', (
    tester,
  ) async {
    // The guard must not make every drag a no-op — the ordinary case has to
    // keep working, or the fix trades a rare crash for a dead feature.
    await pumpDeepScrollback(tester);

    final render = readRenderTerminal(tester);

    final visibleRow = terminal.buffer.lines.length - 2;

    final anchor = terminal.buffer.createAnchor(0, visibleRow);

    render.selectCharactersFrom(anchor, const Offset(80, 40));

    await tester.pump();

    expect(controller.selection, isNotNull);

    final selectedText = terminal.buffer.getText(controller.selection!);

    expect(selectedText, isNotEmpty);
  });
}
