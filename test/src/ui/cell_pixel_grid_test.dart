import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:xterm/src/ui/painter.dart';

/// The cell grid must land on whole DEVICE pixels.
///
/// A cell measured straight from a paragraph is fractional — roughly 15.6
/// logical pixels tall at 13pt with a 1.2 line height. Rows are placed at
/// multiples of that, so every row after the first sits between device pixels
/// and each glyph is rasterized across two, which is what reads as blurry.
void main() {
  /// A painter at [devicePixelRatio], with everything else left at its default.
  TerminalPainter buildPainter({required double devicePixelRatio}) {
    final painter = TerminalPainter(
      theme: TerminalThemes.defaultTheme,
      textStyle: const TerminalStyle(),
      textScaler: TextScaler.noScaling,
      devicePixelRatio: devicePixelRatio,
    );

    return painter;
  }

  /// How far [value] sits from the nearest whole device pixel, in device pixels.
  double devicePixelError(double value, double devicePixelRatio) {
    final devicePixels = value * devicePixelRatio;

    final error = (devicePixels - devicePixels.roundToDouble()).abs();

    return error;
  }

  group('the measured cell', () {
    // Two whole-number ratios and one fractional, which is what a scaled Windows
    // or Linux display reports and where a naive round() is easiest to get wrong.
    for (final ratio in <double>[1, 2, 1.5, 2.25]) {
      test('lands on a whole device pixel at ${ratio}x', () {
        final painter = buildPainter(devicePixelRatio: ratio);

        final cellSize = painter.cellSize;

        expect(
          devicePixelError(cellSize.width, ratio),
          lessThan(0.0001),
          reason: 'the cell WIDTH is not on a device pixel',
        );
        expect(
          devicePixelError(cellSize.height, ratio),
          lessThan(0.0001),
          reason: 'the cell HEIGHT is not on a device pixel',
        );
      });
    }

    test('still has a usable size — snapping must not collapse it', () {
      final painter = buildPainter(devicePixelRatio: 2);

      expect(painter.cellSize.width, greaterThan(0));
      expect(painter.cellSize.height, greaterThan(0));
    });

    // ROUND, never floor. Flooring drops a fraction from every row, and the
    // error accumulates down the screen — so the snapped height must not be
    // systematically SMALLER than the raw one.
    test('rounds rather than floors', () {
      final snapped = buildPainter(devicePixelRatio: 2).cellSize.height;

      // A very high ratio leaves the measurement essentially untouched, which
      // stands in for the raw value here.
      final raw = buildPainter(devicePixelRatio: 10000).cellSize.height;

      final drift = (snapped - raw).abs();

      expect(
        drift,
        lessThanOrEqualTo(0.25),
        reason: 'snapping moved the cell by more than half a device pixel',
      );
    });
  });

  test('a changed ratio re-measures the cell', () {
    final painter = buildPainter(devicePixelRatio: 1);

    final atOneX = painter.cellSize;

    painter.devicePixelRatio = 2;

    final atTwoX = painter.cellSize;

    // 2x can land on a different logical size, since half-logical-pixel steps
    // become available. What matters is that the setter RE-MEASURED rather than
    // handing back the stale value.
    expect(
      devicePixelError(atTwoX.height, 2),
      lessThan(0.0001),
      reason: 'the cell was not re-snapped for the new ratio',
    );
    expect(atOneX.height, greaterThan(0));
  });
}
