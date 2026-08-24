import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Hiding the selection HIGHLIGHT must not disturb the selection.
///
/// On the alternate screen a full-screen program repaints the rows a selection
/// covers rather than scrolling them, so the highlight ends up over characters
/// the user never chose. A host needs to stop drawing it — but clearing the
/// selection would throw away text the user still wants to copy, and would break
/// extending it later. These pin that the two are independent.
void main() {
  late Terminal terminal;
  late TerminalController controller;

  setUp(() {
    terminal = Terminal(maxLines: 100);
    terminal.resize(20, 5);
    terminal.write('first line\r\nsecond line\r\n');

    controller = TerminalController();
  });

  tearDown(() {
    controller.dispose();
  });

  /// Selects the first row, the way a drag across it would.
  void selectFirstRow() {
    final base = terminal.buffer.createAnchor(0, 0);
    final extent = terminal.buffer.createAnchor(5, 0);

    controller.setSelection(base, extent);
  }

  test('the selection is visible by default', () {
    expect(controller.selectionVisible, isTrue);
  });

  test('hiding the highlight leaves the selection intact', () {
    selectFirstRow();

    final selectionBefore = controller.selection;

    expect(selectionBefore, isNotNull);

    controller.setSelectionVisible(false);

    // The whole point: still selected, still readable, just not drawn.
    expect(controller.selectionVisible, isFalse);
    expect(controller.selection, isNotNull);

    final text = terminal.buffer.getText(controller.selection!);

    expect(text, isNotEmpty);
  });

  test('showing it again restores the same selection', () {
    selectFirstRow();

    final textBefore = terminal.buffer.getText(controller.selection!);

    controller.setSelectionVisible(false);
    controller.setSelectionVisible(true);

    expect(controller.selectionVisible, isTrue);

    final textAfter = terminal.buffer.getText(controller.selection!);

    expect(textAfter, textBefore);
  });

  test('a change notifies listeners so the terminal repaints', () {
    var notifyCount = 0;

    void countNotify() {
      notifyCount++;
    }

    controller.addListener(countNotify);

    controller.setSelectionVisible(false);

    expect(notifyCount, 1);

    controller.removeListener(countNotify);
  });

  test('setting the value it already has notifies nobody', () {
    // Guards the hot path: the host calls this on every write, and a repaint per
    // chunk of program output would be its own performance bug.
    var notifyCount = 0;

    void countNotify() {
      notifyCount++;
    }

    controller.addListener(countNotify);

    controller.setSelectionVisible(true);

    expect(notifyCount, 0);

    controller.removeListener(countNotify);
  });

  test('clearing the selection is unaffected by visibility', () {
    selectFirstRow();

    controller.setSelectionVisible(false);
    controller.clearSelection();

    expect(controller.selection, isNull);

    // Visibility is about drawing, not about whether a selection exists — it
    // stays where the host put it.
    expect(controller.selectionVisible, isFalse);
  });
}
