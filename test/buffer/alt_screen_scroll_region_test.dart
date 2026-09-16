import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

/// PINS the geometry a scroll reports: WHICH rows moved and HOW FAR.
///
/// Nothing in the byte stream says how far content shifted, and the buffer
/// afterwards shows only the result — so a host that wants to keep anything
/// pinned to the text it was attached to has to be told. Inferring it by
/// comparing rows is a guess, and a screen of near-identical rows is enough to
/// make the guess wrong.
///
/// The region matters as much as the distance. A full-screen program routinely
/// pins a header or an input box and scrolls only the rows between them, so a
/// host that assumed the whole screen moved would drag everything outside the
/// region along with it.
void main() {
  const altScreenOn = '\x1b[?1049h';

  /// A terminal wired to collect every scroll it reports.
  ({Terminal terminal, List<AltScreenScroll> scrolls}) buildTerminal() {
    final scrolls = <AltScreenScroll>[];

    final terminal = Terminal(maxLines: 100);

    terminal.resize(40, 10);

    terminal.onAltScreenScrolled = scrolls.add;

    final wired = (terminal: terminal, scrolls: scrolls);

    return wired;
  }

  test('a full-screen scroll reports the whole screen as its region', () {
    final wired = buildTerminal();

    wired.terminal.write(altScreenOn);

    for (var number = 1; number <= 12; number++) {
      wired.terminal.write('line $number\r\n');
    }

    expect(wired.scrolls, isNotEmpty);

    final firstScroll = wired.scrolls.first;

    expect(firstScroll.marginTop, 0);
    expect(firstScroll.marginBottom, 9, reason: 'a 10-row screen ends at 9');
    expect(firstScroll.count, 1);
    expect(firstScroll.lines.length, 1);
  });

  test('a scroll REGION reports its own margins, not the screen', () {
    final wired = buildTerminal();

    wired.terminal.write(altScreenOn);

    // A program pinning a header on row 1 and an input box on row 10, and
    // scrolling only what is between them.
    wired.terminal.write('\x1b[2;8r');

    // Park the cursor on the region's last row so the next line feeds scroll
    // the region rather than moving the cursor down.
    wired.terminal.write('\x1b[8;1H');

    for (var number = 1; number <= 4; number++) {
      wired.terminal.write('body $number\r\n');
    }

    expect(wired.scrolls, isNotEmpty);

    final firstScroll = wired.scrolls.first;

    expect(
      firstScroll.marginTop,
      1,
      reason: 'DECSTBM 2;8 is rows 1..7 counting from zero',
    );

    expect(firstScroll.marginBottom, 7);

    expect(
      firstScroll.count,
      1,
      reason: 'one line feed scrolls the region by one row',
    );
  });

  test('a multi-row scroll reports its distance and every lost line', () {
    final wired = buildTerminal();

    wired.terminal.write(altScreenOn);

    for (var number = 1; number <= 10; number++) {
      wired.terminal.write('\x1b[$number;1Hrow $number');
    }

    wired.scrolls.clear();

    // CSI 3 S — scroll the screen up by three rows in one command.
    wired.terminal.write('\x1b[3S');

    expect(wired.scrolls.length, 1, reason: 'one command, one report');

    final scroll = wired.scrolls.first;

    expect(scroll.count, 3);
    expect(scroll.lines.length, 3);

    final lostTexts = <String>[];

    for (final line in scroll.lines) {
      final text = line.getText();

      lostTexts.add(text.trimRight());
    }

    expect(lostTexts, ['row 1', 'row 2', 'row 3']);
  });

  test('the main screen reports nothing — its lines are kept', () {
    final wired = buildTerminal();

    for (var number = 1; number <= 30; number++) {
      wired.terminal.write('main $number\r\n');
    }

    expect(wired.scrolls, isEmpty);
  });
}
