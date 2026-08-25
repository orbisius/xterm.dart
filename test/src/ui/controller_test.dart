import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('TerminalController', () {
    testWidgets('setSelectionRange works', (tester) async {
      final terminal = Terminal();
      final terminalView = TerminalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: terminalView,
          ),
        ),
      ));

      terminalView.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );

      await tester.pump();

      expect(terminalView.selection, isNotNull);
    });

    testWidgets('setSelectionMode changes BufferRange type', (tester) async {
      final terminal = Terminal();
      final terminalView = TerminalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: terminalView,
          ),
        ),
      ));

      terminalView.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );

      expect(terminalView.selection, isA<BufferRangeLine>());

      terminalView.setSelectionMode(SelectionMode.block);

      expect(terminalView.selection, isA<BufferRangeBlock>());
    });

    testWidgets('clearSelection works', (tester) async {
      final terminal = Terminal();
      final terminalView = TerminalController();

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(
            terminal,
            controller: terminalView,
          ),
        ),
      ));

      terminalView.setSelection(
        terminal.buffer.createAnchor(0, 0),
        terminal.buffer.createAnchor(2, 2),
      );

      expect(terminalView.selection, isNotNull);

      terminalView.clearSelection();

      expect(terminalView.selection, isNull);
    });
  });

  group('TerminalController.highlight', () {
    test('works', () {
      final terminal = Terminal();
      final controller = TerminalController();

      final highlight = controller.highlight(
        p1: terminal.buffer.createAnchor(5, 5),
        p2: terminal.buffer.createAnchor(5, 10),
        color: Colors.yellow,
      );
      assert(controller.highlights.length == 1);

      highlight.dispose();
      assert(controller.highlights.isEmpty);
    });

    test('disposing it releases the anchors it holds', () {
      // An anchor stays registered with the line it points at until it is
      // disposed or that line leaves the buffer. Dropping the highlight without
      // releasing them leaves both attached for the life of those lines, and
      // every buffer operation that moves a line walks the anchors on it — so a
      // search re-running per keystroke grew memory and slowed scrolling down.
      final terminal = Terminal();
      final controller = TerminalController();

      final p1 = terminal.buffer.createAnchor(5, 5);
      final p2 = terminal.buffer.createAnchor(5, 10);

      final highlight = controller.highlight(
        p1: p1,
        p2: p2,
        color: Colors.yellow,
      );

      // The precondition, asserted so the test cannot pass against anchors that
      // were never attached in the first place.
      expect(p1.attached, isTrue);
      expect(p2.attached, isTrue);

      highlight.dispose();

      expect(p1.attached, isFalse);
      expect(p2.attached, isFalse);
    });

    test('a disposed highlight reports no range', () {
      // The other half of releasing the anchors: the range is derived from them,
      // so a highlight that has been dropped must stop describing a region.
      final terminal = Terminal();
      final controller = TerminalController();

      final highlight = controller.highlight(
        p1: terminal.buffer.createAnchor(5, 5),
        p2: terminal.buffer.createAnchor(5, 10),
        color: Colors.yellow,
      );

      expect(highlight.range, isNotNull);

      highlight.dispose();

      expect(highlight.range, isNull);
    });

    test('disposing one highlight leaves another one alone', () {
      // Each highlight owns ITS anchors and nothing else — the release must not
      // reach across to a highlight the caller still holds.
      final terminal = Terminal();
      final controller = TerminalController();

      final firstHighlight = controller.highlight(
        p1: terminal.buffer.createAnchor(0, 0),
        p2: terminal.buffer.createAnchor(4, 0),
        color: Colors.yellow,
      );

      final secondHighlight = controller.highlight(
        p1: terminal.buffer.createAnchor(0, 1),
        p2: terminal.buffer.createAnchor(4, 1),
        color: Colors.yellow,
      );

      firstHighlight.dispose();

      expect(secondHighlight.range, isNotNull);
      expect(controller.highlights, contains(secondHighlight));
    });
  });
}
