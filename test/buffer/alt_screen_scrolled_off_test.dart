import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// The alternate screen keeps no scrollback, so a line pushed past its top
/// margin is overwritten and gone. `onAltScreenLineScrolledOff` is the only
/// point at which that line still holds its content — these pin that it fires
/// for every lost line, in order, and never for the main screen.
void main() {
  const altScreenOn = '\x1b[?1049h';

  /// A terminal wired to collect the lines the alternate screen loses.
  ({Terminal terminal, List<String> scrolledOff}) buildTerminal() {
    final scrolledOff = <String>[];

    final terminal = Terminal(maxLines: 100);

    terminal.resize(40, 5);

    terminal.onAltScreenLineScrolledOff = (line) {
      final text = line.getText();

      scrolledOff.add(text.trimRight());
    };

    final wired = (terminal: terminal, scrolledOff: scrolledOff);

    return wired;
  }

  test('every line the alternate screen loses is reported, in order', () {
    final wired = buildTerminal();

    wired.terminal.write(altScreenOn);

    // 5 rows tall, so writing 20 lines pushes 15 of them off the top.
    for (var number = 1; number <= 20; number++) {
      wired.terminal.write('line $number\r\n');
    }

    // Every lost line, oldest first, with no gaps — asserted as the sequence
    // rather than a hand-counted total, which depends on where the last
    // newline leaves the cursor.
    final expected = <String>[];

    for (var number = 1; number <= wired.scrolledOff.length; number++) {
      expected.add('line $number');
    }

    expect(wired.scrolledOff, expected);

    // A 5-row screen cannot have kept more than 5, so the bulk really did
    // leave — this is the whole point of the callback.
    expect(wired.scrolledOff.length, greaterThanOrEqualTo(15));

    // And nothing still on screen was reported as lost.
    final lastKept = 'line ${wired.scrolledOff.length + 1}';

    expect(wired.scrolledOff.contains(lastKept), isFalse);
  });

  test('the MAIN screen reports nothing — its lines are retained', () {
    final wired = buildTerminal();

    for (var number = 1; number <= 20; number++) {
      wired.terminal.write('line $number\r\n');
    }

    expect(wired.scrolledOff, isEmpty);
  });

  test('no callback set is not an error', () {
    final terminal = Terminal(maxLines: 100);

    terminal.resize(40, 5);

    terminal.write(altScreenOn);

    for (var number = 1; number <= 20; number++) {
      terminal.write('line $number\r\n');
    }

    expect(terminal.buffer.height, 5);
  });
}
