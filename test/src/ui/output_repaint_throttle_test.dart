import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/render.dart';
import 'package:xterm/xterm.dart';

/// Output-driven relayouts obey [TerminalController.outputRepaintInterval].
///
/// Measured need: draining a 300k-line flood took 11.7s with the window
/// visible and 5.1s with it hidden — the layout/paint pipeline was ~70% of the
/// drain, spent on frames that scroll away unread. The interval lets a host
/// cap that cadence while it drains, without touching what ends up on screen.
void main() {
  late Terminal terminal;
  late TerminalController controller;

  Future<void> pumpTerminal(WidgetTester tester) async {
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
  }

  RenderTerminal readRenderTerminal(WidgetTester tester) {
    final state = tester.state<TerminalViewState>(find.byType(TerminalView));

    return state.renderTerminal;
  }

  testWidgets('without an interval every output change lays out', (
    tester,
  ) async {
    await pumpTerminal(tester);

    final render = readRenderTerminal(tester);

    terminal.write('hello');

    expect(render.debugNeedsLayout, isTrue);
  });

  testWidgets('inside the interval a change is not drawn', (tester) async {
    await pumpTerminal(tester);

    final render = readRenderTerminal(tester);

    // Longer than any test run, so the second write always lands inside it.
    controller.setOutputRepaintInterval(const Duration(minutes: 5));

    await tester.pump();

    // The FIRST throttled change lays out immediately — the cap is on the
    // cadence, never a delay before the first frame.
    terminal.write('first');

    expect(render.debugNeedsLayout, isTrue);

    await tester.pump();

    terminal.write('second');

    expect(render.debugNeedsLayout, isFalse);
  });

  testWidgets('clearing the interval draws the final state', (tester) async {
    await pumpTerminal(tester);

    final render = readRenderTerminal(tester);

    controller.setOutputRepaintInterval(const Duration(minutes: 5));

    await tester.pump();

    terminal.write('first');

    await tester.pump();

    // Swallowed by the gate — this is the content that must not be lost.
    terminal.write('final state');

    expect(render.debugNeedsLayout, isFalse);

    // The drain ends: clearing the interval notifies through the controller,
    // which is what guarantees the swallowed content reaches the screen.
    controller.setOutputRepaintInterval(null);

    expect(render.debugNeedsLayout, isTrue);
  });
}
