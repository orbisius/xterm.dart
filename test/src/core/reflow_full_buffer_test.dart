import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// Reflowing a FULL scrollback — what changing the font size does once the
/// buffer has wrapped around at least once.
void main() {
  test('narrowing a full scrollback does not throw', () {
    final terminal = Terminal(maxLines: 30);
    terminal.resize(80, 24);

    // Past maxLines on purpose: the buffer must have evicted, so the backing
    // array has wrapped and index 0 is no longer slot 0.
    for (var number = 1; number <= 200; number++) {
      terminal.write('line $number\r\n');
    }

    terminal.resize(40, 24);

    expect(terminal.viewWidth, 40);
  });

  test('widening a full scrollback does not throw', () {
    final terminal = Terminal(maxLines: 30);
    terminal.resize(40, 24);

    for (var number = 1; number <= 200; number++) {
      terminal.write('a longer line of output number $number\r\n');
    }

    terminal.resize(100, 24);

    expect(terminal.viewWidth, 100);
  });

  test('widening WRAPPED lines in a wrapped-around buffer does not throw', () {
    // The combination that breaks it: the backing array has wrapped (start
    // index is not 0), and the reflow yields FEWER lines than the buffer holds
    // because wrapped fragments merge back together. That is what happens when
    // the font gets SMALLER — more columns, so long lines stop wrapping.
    final terminal = Terminal(maxLines: 40);
    terminal.resize(20, 10);

    final longLine = 'x' * 100;

    for (var number = 1; number <= 100; number++) {
      terminal.write('$longLine\r\n');
    }

    terminal.resize(200, 10);

    expect(terminal.viewWidth, 200);
  });

  test('repeated resizes on a full scrollback stay consistent', () {
    // A font drag fires several resizes in a row; each one reflows what the
    // previous one produced.
    final terminal = Terminal(maxLines: 30);
    terminal.resize(80, 24);

    for (var number = 1; number <= 200; number++) {
      terminal.write('line $number with some trailing text\r\n');
    }

    for (final width in [60, 45, 30, 55, 90]) {
      terminal.resize(width, 24);
    }

    expect(terminal.buffer.lines.length, greaterThan(0));
  });
}
