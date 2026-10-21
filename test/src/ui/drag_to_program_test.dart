import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// A program that asked for the mouse gets the DRAG too: the press, each cell
/// the pointer reaches while the button is held, and the release. That is how a
/// full-screen program selects its own text and copies it whole, without the
/// line breaks it drew. A double click goes to it the same way, whole, and the
/// terminal selects no word under it. Everything stays the terminal's own
/// selection when the program did not ask, when the host did not hand that
/// input over, and when Shift is held.
void main() {
  /// The modes an agent CLI turns on, in the order it sends them; the last
  /// tracking mode set is the one in force.
  const agentCliMouseModes = '\x1b[?1000h\x1b[?1002h\x1b[?1003h\x1b[?1006h';

  const pressCell = CellOffset(2, 1);
  const middleCell = CellOffset(6, 1);
  const releaseCell = CellOffset(10, 1);

  /// A mounted view over [terminal] whose controller hands [inputs] to it.
  Future<TerminalController> pumpView({
    required WidgetTester tester,
    required Terminal terminal,
    required PointerInputs inputs,
  }) async {
    final controller = TerminalController(pointerInputs: inputs);

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal, controller: controller),
        ),
      ),
    );

    return controller;
  }

  /// The global position of the middle of [cell].
  Offset cellCenter({required WidgetTester tester, required CellOffset cell}) {
    final viewState = tester.state<TerminalViewState>(
      find.byType(TerminalView),
    );

    final renderTerminal = viewState.renderTerminal;

    final cellTopLeft = renderTerminal.getOffset(cell);

    final cellSize = renderTerminal.cellSize;

    final localCenter =
        cellTopLeft + Offset(cellSize.width / 2, cellSize.height / 2);

    final globalCenter = renderTerminal.localToGlobal(localCenter);

    return globalCenter;
  }

  /// A mouse drag with the primary button: down on [pressCell], through
  /// [middleCell], up on [releaseCell]. [holdBeforeMoving] keeps the button
  /// down in place first, long enough for a tap to register its press.
  Future<void> dragAcrossThreeCells(
    WidgetTester tester, {
    Duration holdBeforeMoving = Duration.zero,
  }) async {
    final pressPoint = cellCenter(tester: tester, cell: pressCell);
    final middlePoint = cellCenter(tester: tester, cell: middleCell);
    final releasePoint = cellCenter(tester: tester, cell: releaseCell);

    final gesture = await tester.startGesture(
      pressPoint,
      kind: PointerDeviceKind.mouse,
    );

    await tester.pump(holdBeforeMoving);

    await gesture.moveTo(middlePoint);
    await tester.pump();

    await gesture.moveTo(releasePoint);
    await tester.pump();

    await gesture.up();
    await tester.pump();
  }

  /// A primary-button mouse click on [cell], [clickCount] times in a row, then
  /// enough time for the double-click window to close, so no timer is left.
  Future<void> clickOn({
    required WidgetTester tester,
    required CellOffset cell,
    int clickCount = 1,
  }) async {
    final clickPoint = cellCenter(tester: tester, cell: cell);

    for (var clickIndex = 0; clickIndex < clickCount; clickIndex++) {
      await tester.tapAt(clickPoint, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.pump(kDoubleTapTimeout);
  }

  // SGR reports are 1-based: cell (2, 1) is column 3, row 2. Motion with the
  // left button held is button 0 + 32; the release is the button with `m`.
  const buttonMotionReports = <String>[
    '\x1b[<0;3;2M',
    '\x1b[<32;7;2M',
    '\x1b[<32;11;2M',
    '\x1b[<0;11;2m',
  ];

  testWidgets(
    'the modes an agent CLI turns on: the drag reaches the program, not the '
    'selection',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write(agentCliMouseModes);

      final controller = await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs.all(),
      );

      await dragAcrossThreeCells(tester);

      expect(output, buttonMotionReports);
      expect(controller.selection, isNull);
    },
  );

  testWidgets(
    'button-event tracking (1002): press, motion while held, release',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1002h\x1b[?1006h');

      final controller = await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs.all(),
      );

      await dragAcrossThreeCells(tester);

      expect(output, buttonMotionReports);
      expect(controller.selection, isNull);
    },
  );

  testWidgets(
    'a drag that waits before moving still sends ONE press, and its release',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1002h\x1b[?1006h');

      final controller = await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs.all(),
      );

      // Longer than kPressTimeout, so the tap reports its press before the
      // drag starts.
      await dragAcrossThreeCells(
        tester,
        holdBeforeMoving: const Duration(milliseconds: 150),
      );

      expect(output, buttonMotionReports);
      expect(controller.selection, isNull);
    },
  );

  testWidgets(
    'press-and-release tracking (1000): the press and the release, no motion',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1000h\x1b[?1006h');

      final controller = await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs.all(),
      );

      await dragAcrossThreeCells(tester);

      expect(output, <String>['\x1b[<0;3;2M', '\x1b[<0;11;2m']);
      expect(controller.selection, isNull);
    },
  );

  testWidgets(
    'boundary: a program that asked for no mouse keeps the drag a selection',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      final controller = await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs.all(),
      );

      await dragAcrossThreeCells(tester);

      expect(output, isEmpty);
      expect(controller.selection, isNotNull);
    },
  );

  testWidgets(
    'boundary: a host that keeps drags (no PointerInput.drag) still selects',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write(agentCliMouseModes);

      final controller = await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs({PointerInput.tap}),
      );

      await dragAcrossThreeCells(tester);

      expect(output, isEmpty);
      expect(controller.selection, isNotNull);
    },
  );

  testWidgets(
    'a host that keeps drags releases the press its tap reported, then selects',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1002h\x1b[?1006h');

      final controller = await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs({PointerInput.tap}),
      );

      // Longer than kPressTimeout, so the tap reports its press before the
      // drag starts.
      await dragAcrossThreeCells(
        tester,
        holdBeforeMoving: const Duration(milliseconds: 150),
      );

      expect(output, <String>['\x1b[<0;3;2M', '\x1b[<0;3;2m']);
      expect(controller.selection, isNotNull);
    },
  );

  testWidgets(
    'a double click in a mouse program reaches it whole and selects no word',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1000h\x1b[?1006h');
      terminal.write('hello world');

      final controller = await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs.all(),
      );

      await clickOn(
        tester: tester,
        cell: const CellOffset(2, 0),
        clickCount: 2,
      );

      expect(output, <String>[
        '\x1b[<0;3;1M',
        '\x1b[<0;3;1m',
        '\x1b[<0;3;1M',
        '\x1b[<0;3;1m',
      ]);
      expect(controller.selection, isNull);
    },
  );

  testWidgets(
    'boundary: a double click with no mouse program selects the word',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('hello world');

      final controller = await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs.all(),
      );

      await clickOn(
        tester: tester,
        cell: const CellOffset(2, 0),
        clickCount: 2,
      );

      expect(output, isEmpty);
      expect(controller.selection, isNotNull);
    },
  );

  testWidgets(
    'Shift+click in a mouse program stays with the terminal',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write('\x1b[?1000h\x1b[?1006h');

      await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs.all(),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      await clickOn(tester: tester, cell: pressCell);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(output, isEmpty);
    },
  );

  testWidgets(
    'boundary: Shift held keeps the drag a selection in a mouse program',
    (tester) async {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add);

      terminal.write(agentCliMouseModes);

      final controller = await pumpView(
        tester: tester,
        terminal: terminal,
        inputs: const PointerInputs.all(),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

      await dragAcrossThreeCells(tester);

      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      expect(output, isEmpty);
      expect(controller.selection, isNotNull);
    },
  );
}
