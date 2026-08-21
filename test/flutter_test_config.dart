import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// How much of a golden image may differ before it counts as a failure, as a
/// ratio where 1.0 is the whole image.
///
/// Text is rasterized slightly differently from one machine to the next — the
/// same glyphs in the same places, with their antialiased edges blended a shade
/// apart. The scaled-text goldens are where that shows, because a fractional
/// text scale lands glyph edges on sub-pixel boundaries and the rounding is not
/// identical everywhere. Measured: 0.06% at 1x and 0.13% at 2x, the doubling
/// being what twice as many edge pixels produces.
///
/// A regression that MOVES something — a mis-snapped cell grid, a shifted
/// baseline, a wrong scale — redraws whole glyphs and changes whole percent. So
/// this sits about eight times above the observed noise and far below a real
/// fault.
const double _goldenToleranceRatio = 0.005;

/// A golden comparator that accepts a difference under [_goldenToleranceRatio].
///
/// The stock comparator demands an exact match, which no two machines can agree
/// on for antialiased text: goldens regenerated on one machine then fail on the
/// other, and regenerating there hands the failure straight back.
class TolerantGoldenComparator extends LocalFileComparator {
  TolerantGoldenComparator(super.testFile);

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final goldenBytes = await getGoldenBytes(golden);

    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      goldenBytes,
    );

    if (result.passed) {
      return true;
    }

    if (result.diffPercent <= _goldenToleranceRatio) {
      return true;
    }

    final failureText = await generateFailureOutput(result, golden, basedir);

    throw FlutterError(failureText);
  }
}

/// Flutter loads this file before the suite and runs [testMain] through it,
/// which is the sanctioned place to swap the golden comparator.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final defaultComparator = goldenFileComparator as LocalFileComparator;

  // LocalFileComparator takes the TEST FILE and keeps its directory, so a file
  // name has to be appended to a basedir that is already a directory — dirname
  // then gives the same basedir back.
  final testFile = Uri.parse(
    '${defaultComparator.basedir}flutter_test_config.dart',
  );

  goldenFileComparator = TolerantGoldenComparator(testFile);

  await testMain();
}
