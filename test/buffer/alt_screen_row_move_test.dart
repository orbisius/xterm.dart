import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// PINS that EVERY operation moving alternate-screen rows reports it.
///
/// A host that keeps anything pinned to the text it was attached to needs the
/// whole account of a burst, not part of it. `scrollUp` is only one of four ways
/// rows move: `scrollDown` and `reverseIndex` push them the other way, and
/// `insertLines` / `deleteLines` move everything from the CURSOR down. A host
/// told about one of them and not the others moves its anchors by the reported
/// part and is silently wrong by the rest — worse than being told nothing,
/// because a partial answer looks authoritative.
///
/// [AltScreenScroll.count] is signed, so all four arrive as one event and a row
/// lands at `row - count` in every direction.
void main() {
  const altScreenOn = '\x1b[?1049h';

  /// A terminal wired to collect every row move it reports.
  ({Terminal terminal, List<AltScreenScroll> moves}) buildTerminal() {
    final moves = <AltScreenScroll>[];

    final terminal = Terminal(maxLines: 100);

    terminal.resize(40, 10);

    terminal.onAltScreenScrolled = moves.add;

    final wired = (terminal: terminal, moves: moves);

    return wired;
  }

  /// Fills every screen row with a line that names it.
  void paintNumberedRows({required Terminal terminal}) {
    for (var row = 1; row <= 10; row++) {
      terminal.write('\x1b[$row;1Hrow $row');
    }
  }

  test('scrolling DOWN reports a negative count', () {
    final wired = buildTerminal();

    wired.terminal.write(altScreenOn);

    paintNumberedRows(terminal: wired.terminal);

    wired.moves.clear();

    // CSI 2 T — scroll the screen down by two rows.
    wired.terminal.write('\x1b[2T');

    expect(wired.moves.length, 1, reason: 'one command, one report');

    final move = wired.moves.first;

    expect(move.count, -2, reason: 'down is negative, so row - count moves down');
    expect(move.marginTop, 0);
    expect(move.marginBottom, 9);
  });

  test('scrolling DOWN loses the region BOTTOM rows, in screen order', () {
    final wired = buildTerminal();

    wired.terminal.write(altScreenOn);

    paintNumberedRows(terminal: wired.terminal);

    wired.moves.clear();

    wired.terminal.write('\x1b[2T');

    final lostTexts = <String>[];

    for (final line in wired.moves.first.lines) {
      final text = line.getText();

      lostTexts.add(text.trimRight());
    }

    expect(
      lostTexts,
      ['row 9', 'row 10'],
      reason: 'the bottom rows leave when the region moves down',
    );
  });

  test('deleteLines reports rows moving up from the CURSOR', () {
    final wired = buildTerminal();

    wired.terminal.write(altScreenOn);

    paintNumberedRows(terminal: wired.terminal);

    wired.moves.clear();

    // Park on screen row 3 (1-indexed), then delete two lines.
    wired.terminal.write('\x1b[4;1H');
    wired.terminal.write('\x1b[2M');

    expect(wired.moves.length, 1);

    final move = wired.moves.first;

    expect(move.count, 2, reason: 'rows below the cursor move UP');
    expect(
      move.marginTop,
      3,
      reason: 'the region that moves starts at the cursor, not the top margin',
    );
    expect(move.marginBottom, 9);

    final lostTexts = <String>[];

    for (final line in move.lines) {
      final text = line.getText();

      lostTexts.add(text.trimRight());
    }

    expect(lostTexts, ['row 4', 'row 5']);
  });

  test('insertLines reports rows moving down from the CURSOR', () {
    final wired = buildTerminal();

    wired.terminal.write(altScreenOn);

    paintNumberedRows(terminal: wired.terminal);

    wired.moves.clear();

    wired.terminal.write('\x1b[4;1H');
    wired.terminal.write('\x1b[2L');

    expect(wired.moves.length, 1);

    final move = wired.moves.first;

    expect(move.count, -2, reason: 'rows below the cursor move DOWN');
    expect(move.marginTop, 3);
    expect(move.marginBottom, 9);

    final lostTexts = <String>[];

    for (final line in move.lines) {
      final text = line.getText();

      lostTexts.add(text.trimRight());
    }

    expect(
      lostTexts,
      ['row 9', 'row 10'],
      reason: 'the region pushes its bottom rows off when it moves down',
    );
  });

  test('a burst that mixes movers reports EVERY one of them', () {
    final wired = buildTerminal();

    wired.terminal.write(altScreenOn);

    paintNumberedRows(terminal: wired.terminal);

    wired.moves.clear();

    // The shape a host gets wrong when only one mover reports: a delete and a
    // scroll in one burst move content by their SUM, and a host told about one
    // of them lands short by the other.
    wired.terminal.write('\x1b[1;1H');
    wired.terminal.write('\x1b[1M');
    wired.terminal.write('\x1b[1S');

    expect(wired.moves.length, 2, reason: 'both movers must report');

    var netMove = 0;

    for (final move in wired.moves) {
      netMove += move.count;
    }

    expect(netMove, 2, reason: 'one row up from each, so two rows in total');
  });

  test('the main screen still reports nothing', () {
    final wired = buildTerminal();

    paintNumberedRows(terminal: wired.terminal);

    wired.terminal.write('\x1b[2T');
    wired.terminal.write('\x1b[4;1H');
    wired.terminal.write('\x1b[2M');

    expect(wired.moves, isEmpty);
  });
}
