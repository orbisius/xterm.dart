import 'dart:ui';
import 'package:flutter/painting.dart';

import 'package:xterm/src/ui/palette_builder.dart';
import 'package:xterm/src/ui/paragraph_cache.dart';
import 'package:xterm/xterm.dart';

/// Encapsulates the logic for painting various terminal elements.
class TerminalPainter {
  TerminalPainter({
    required TerminalTheme theme,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    required double devicePixelRatio,
  })  : _textStyle = textStyle,
        _theme = theme,
        _textScaler = textScaler,
        _devicePixelRatio = devicePixelRatio;

  /// A lookup table from terminal colors to Flutter colors.
  late var _colorPalette = PaletteBuilder(_theme).build();

  /// Size of each character in the terminal.
  late var _cellSize = _measureCharSize();

  /// How many paragraphs [_paragraphCache] keeps: the runs and lone cells of a
  /// tall screen several times over. A run's paragraph is far larger than a
  /// single cell's, so a bigger cache only keeps memory for text long gone.
  static const _paragraphCacheSize = 1024;

  /// The cached for cells in the terminal. Should be cleared when the same
  /// cell no longer produces the same visual output. For example, when
  /// [_textStyle] is changed, or when the system font changes.
  final _paragraphCache = ParagraphCache(_paragraphCacheSize);

  /// The advance of a printable ASCII character per bold / italic combination,
  /// or null for a font whose characters differ in width. Measured on first
  /// use by [_resolveRunAdvance], cleared when the font or its scale changes.
  final _runAdvanceByStyle = <int, double?>{};

  TerminalStyle get textStyle => _textStyle;
  TerminalStyle _textStyle;
  set textStyle(TerminalStyle value) {
    if (value == _textStyle) {
      return;
    }

    _textStyle = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _runAdvanceByStyle.clear();
  }

  TextScaler get textScaler => _textScaler;
  TextScaler _textScaler = TextScaler.linear(1.0);
  set textScaler(TextScaler value) {
    if (value == _textScaler) {
      return;
    }

    _textScaler = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _runAdvanceByStyle.clear();
  }

  /// The display's device pixels per logical pixel, used to snap the cell grid
  /// to whole DEVICE pixels — see [_measureCharSize].
  ///
  /// Changes when the window moves to a display with a different scale factor,
  /// which re-measures and so can change the terminal's size in cells.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) {
      return;
    }

    _devicePixelRatio = value;
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
  }

  TerminalTheme get theme => _theme;
  TerminalTheme _theme;
  set theme(TerminalTheme value) {
    if (value == _theme) {
      return;
    }

    _theme = value;
    _colorPalette = PaletteBuilder(value).build();
    _paragraphCache.clear();
  }

  Size _measureCharSize() {
    const test = 'mmmmmmmmmm';

    final textStyle = _textStyle.toTextStyle();
    final paragraph = _layoutProbe(style: textStyle, text: test);

    final result = Size(
      _snapToDevicePixels(paragraph.maxIntrinsicWidth / test.length),
      _snapToDevicePixels(paragraph.height),
    );

    paragraph.dispose();
    return result;
  }

  /// Lays out [text] in [style] at the current text scale, for measuring. The
  /// caller disposes the paragraph.
  Paragraph _layoutProbe({required TextStyle style, required String text}) {
    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.pushStyle(
      style.getTextStyle(textScaler: _textScaler),
    );

    builder.addText(text);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: double.infinity));

    return paragraph;
  }

  /// Rounds a measured extent to a whole DEVICE pixel.
  ///
  /// A cell measured straight from the paragraph is fractional — at 13pt with a
  /// 1.2 line height it is about 15.6 logical pixels tall. Every row and column
  /// is then placed at a multiple of that, so all but the first land between
  /// device pixels and each glyph is rasterized across two, which reads as
  /// blurry text next to a terminal that snaps its grid.
  ///
  /// ROUND, never floor: flooring drops a fraction of a pixel from every row,
  /// and the error accumulates down the screen.
  double _snapToDevicePixels(double value) {
    if (_devicePixelRatio <= 0) {
      return value;
    }

    final devicePixels = (value * _devicePixelRatio).round();

    final snapped = devicePixels / _devicePixelRatio;

    return snapped;
  }

  /// The size of each character in the terminal.
  Size get cellSize => _cellSize;

  /// When the set of font available to the system changes, call this method to
  /// clear cached state related to font rendering.
  void clearFontCache() {
    _cellSize = _measureCharSize();
    _paragraphCache.clear();
    _runAdvanceByStyle.clear();
  }

  /// Paints the cursor based on the current cursor type.
  void paintCursor(
    Canvas canvas,
    Offset offset, {
    required TerminalCursorType cursorType,
    bool hasFocus = true,
  }) {
    final paint = Paint()
      ..color = _theme.cursor
      ..strokeWidth = 1;

    if (!hasFocus) {
      paint.style = PaintingStyle.stroke;
      canvas.drawRect(offset & _cellSize, paint);
      return;
    }

    switch (cursorType) {
      case TerminalCursorType.block:
        paint.style = PaintingStyle.fill;
        canvas.drawRect(offset & _cellSize, paint);
        return;
      case TerminalCursorType.underline:
        return canvas.drawLine(
          Offset(offset.dx, _cellSize.height - 1),
          Offset(offset.dx + _cellSize.width, _cellSize.height - 1),
          paint,
        );
      case TerminalCursorType.verticalBar:
        return canvas.drawLine(
          Offset(offset.dx, 0),
          Offset(offset.dx, _cellSize.height),
          paint,
        );
    }
  }

  @pragma('vm:prefer-inline')
  void paintHighlight(Canvas canvas, Offset offset, int length, Color color) {
    final endOffset =
        offset.translate(length * _cellSize.width, _cellSize.height);

    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;

    canvas.drawRect(
      Rect.fromPoints(offset, endOffset),
      paint,
    );
  }

  /// Marks a background code read from an inverse cell's FOREGROUND, which
  /// resolves through [resolveForegroundColor]. It sits above the color type
  /// bits ([CellColor.typeMask]), so no stored color has it set.
  static const _inverseBackgroundBit = 1 << 27;

  /// The background code of a cell that paints no background.
  static const _noBackgroundCode = -1;

  /// The cell flags a character's text style reads; two cells join one run of
  /// text only when these match.
  static const _textStyleFlags = CellFlags.bold |
      CellFlags.faint |
      CellFlags.italic |
      CellFlags.underline |
      CellFlags.inverse;

  /// Printable ASCII, space to tilde: the characters a run of text may hold.
  static const _firstRunCodePoint = 0x20;
  static const _lastRunCodePoint = 0x7E;

  static const _spaceCodePoint = 0x20;
  static const _noBreakSpaceCodePoint = 0xA0;

  /// A run draws each character in its own cell, as the cell-by-cell path
  /// does, so a font's ligatures (`->` drawn as one arrow) stay off.
  static const _ligaturesOff = [
    FontFeature.disable('liga'),
    FontFeature.disable('calt'),
    FontFeature.disable('clig'),
  ];

  /// How far ten wide and ten narrow characters may differ in width, in logical
  /// pixels, for a font to count as one where every character has one advance.
  static const _monospaceTolerance = 0.01;

  /// Paints [line] to [canvas] at [offset]. The x offset of [offset] is usually
  /// 0, and the y offset is the top of the line.
  ///
  /// Text is painted one paragraph per run of same-style printable ASCII, held
  /// on the cell grid; every other character in its own cell.
  void paintLine(
    Canvas canvas,
    Offset offset,
    BufferLine line,
  ) {
    _paintLineBackgrounds(canvas, offset, line);

    final cellData = CellData.empty();
    final cellWidth = _cellSize.width;
    final lineLength = line.length;

    var i = 0;

    while (i < lineLength) {
      final runEnd = _findTextRunEnd(line, i);

      if (runEnd > i) {
        _paintTextRun(
          canvas,
          offset,
          line: line,
          start: i,
          end: runEnd,
          cellData: cellData,
        );

        i = runEnd;
        continue;
      }

      line.getCellData(i, cellData);

      final cellOffset = offset.translate(i * cellWidth, 0);

      paintCellForeground(canvas, cellOffset, cellData);

      final charWidth = cellData.content >> CellContent.widthShift;

      if (charWidth == 2) {
        i += 2;
      } else {
        i++;
      }
    }
  }

  /// Where the run of text starting at [start] ends: the cells after it that
  /// hold printable ASCII in the same text style. Returns [start] when the cell
  /// there starts no run, so it is painted on its own.
  ///
  /// A run holds printable ASCII only, one cell per character, which the
  /// terminal's font draws at one advance; a wide character, box drawing, or
  /// anything a fallback font may draw keeps its own cell. A font whose
  /// characters differ in width draws no runs at all.
  int _findTextRunEnd(BufferLine line, int start) {
    if (!_isRunCell(line, start)) {
      return start;
    }

    final runFlags = line.getAttributes(start) & _textStyleFlags;
    final runAdvance = _resolveRunAdvance(runFlags);

    if (runAdvance == null) {
      return start;
    }

    // Every cell of the run has runFlags, the inverse bit included, so which
    // color the text draws in is known once, before the loop.
    final isInverseRun = runFlags & CellFlags.inverse != 0;

    final runColorCode = _readTextColorCode(
      line,
      start,
      isInverse: isInverseRun,
    );

    final lineLength = line.length;

    var end = start + 1;

    while (end < lineLength &&
        _isRunCell(line, end) &&
        line.getAttributes(end) & _textStyleFlags == runFlags &&
        _readTextColorCode(line, end, isInverse: isInverseRun) ==
            runColorCode) {
      end++;
    }

    return end;
  }

  /// Whether the cell at [index] holds one printable ASCII character.
  bool _isRunCell(BufferLine line, int index) {
    final content = line.getContent(index);
    final codePoint = content & CellContent.codepointMask;
    final isSingleWidth = content >> CellContent.widthShift == 1;

    final isRunCell = isSingleWidth &&
        codePoint >= _firstRunCodePoint &&
        codePoint <= _lastRunCodePoint;

    return isRunCell;
  }

  /// The stored color a cell's text draws in: its background when [isInverse],
  /// else its foreground. Inverse is one of [_textStyleFlags], so two cells
  /// with equal flags and an equal code draw in the same color.
  int _readTextColorCode(
    BufferLine line,
    int index, {
    required bool isInverse,
  }) {
    if (isInverse) {
      final backgroundCode = line.getBackground(index);

      return backgroundCode;
    }

    final foregroundCode = line.getForeground(index);

    return foregroundCode;
  }

  /// Paints the cells from [start] up to [end] of [line] as one paragraph.
  ///
  /// The letter spacing makes every character advance exactly one cell, so the
  /// run sits on the same grid as a cell painted alone, the cursor and a
  /// selection. Blank spaces at either end draw nothing unless underlined.
  void _paintTextRun(
    Canvas canvas,
    Offset offset, {
    required BufferLine line,
    required int start,
    required int end,
    required CellData cellData,
  }) {
    line.getCellData(start, cellData);

    final runFlags = cellData.flags & _textStyleFlags;
    final trimsBlankEnds = runFlags & CellFlags.underline == 0;

    var textStart = start;
    var textEnd = end;

    if (trimsBlankEnds) {
      while (textStart < textEnd &&
          line.getCodePoint(textStart) == _spaceCodePoint) {
        textStart++;
      }

      while (textEnd > textStart &&
          line.getCodePoint(textEnd - 1) == _spaceCodePoint) {
        textEnd--;
      }
    }

    if (textStart == textEnd) {
      return;
    }

    final runCodePoints = <int>[];

    for (var i = textStart; i < textEnd; i++) {
      var codePoint = line.getCodePoint(i);

      // An underline is drawn below a no-break space at a run's ends too, where
      // it is left off below a plain space.
      if (!trimsBlankEnds && codePoint == _spaceCodePoint) {
        codePoint = _noBreakSpaceCodePoint;
      }

      runCodePoints.add(codePoint);
    }

    final runText = String.fromCharCodes(runCodePoints);

    // The whole style and the text, so two different runs never share a key:
    // "16777216:0:1:git status"
    final cacheKey =
        '${cellData.foreground}:${cellData.background}:$runFlags:$runText';

    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      // _findTextRunEnd starts a run only in a style that has an advance.
      final runAdvance = _resolveRunAdvance(runFlags) ?? _cellSize.width;
      final cellStyle = _resolveCellTextStyle(cellData);

      final runStyle = cellStyle.copyWith(
        letterSpacing: _cellSize.width - runAdvance,
        fontFeatures: _ligaturesOff,
      );

      paragraph = _paragraphCache.performAndCacheLayout(
        runText,
        runStyle,
        _textScaler,
        cacheKey,
      );
    }

    final runOffset = offset.translate(textStart * _cellSize.width, 0);

    canvas.drawParagraph(paragraph, runOffset);
  }

  /// The advance every printable ASCII character has in the bold / italic
  /// style [flags] select, or null when the font draws characters at different
  /// widths, where text is painted cell by cell. Measured once per style.
  double? _resolveRunAdvance(int flags) {
    final styleKey = flags & (CellFlags.bold | CellFlags.italic);

    if (_runAdvanceByStyle.containsKey(styleKey)) {
      final cachedAdvance = _runAdvanceByStyle[styleKey];

      return cachedAdvance;
    }

    const wideSample = 'mmmmmmmmmm';
    const narrowSample = 'iiiiiiiiii';

    var style = _textStyle.toTextStyle(
      bold: styleKey & CellFlags.bold != 0,
      italic: styleKey & CellFlags.italic != 0,
    );
    style = style.copyWith(fontFeatures: _ligaturesOff);

    final wideParagraph = _layoutProbe(style: style, text: wideSample);
    final narrowParagraph = _layoutProbe(style: style, text: narrowSample);
    final wideWidth = wideParagraph.maxIntrinsicWidth;
    final narrowWidth = narrowParagraph.maxIntrinsicWidth;

    wideParagraph.dispose();
    narrowParagraph.dispose();

    final double? runAdvance;

    if ((wideWidth - narrowWidth).abs() <= _monospaceTolerance) {
      runAdvance = wideWidth / wideSample.length;
    } else {
      runAdvance = null;
    }

    _runAdvanceByStyle[styleKey] = runAdvance;

    return runAdvance;
  }

  /// Paints the backgrounds of [line], one rectangle per run of adjacent cells
  /// that share a color, before any of the line's text.
  ///
  /// Per run, not per cell: a program with its own color scheme gives every
  /// cell a background, and a rectangle per cell is tens of thousands of draw
  /// calls a frame. With every background down first, a glyph that reaches
  /// past its cell is no longer covered by the next cell's background.
  void _paintLineBackgrounds(Canvas canvas, Offset offset, BufferLine line) {
    final lineLength = line.length;

    var runStart = 0;
    var runCode = _noBackgroundCode;

    for (var i = 0; i < lineLength; i++) {
      final cellCode = _readBackgroundCode(line, i);

      if (cellCode != runCode) {
        _paintBackgroundRun(
          canvas,
          offset,
          code: runCode,
          start: runStart,
          end: i,
        );

        runStart = i;
        runCode = cellCode;
      }

      // A wide character's background covers both of its cells, whatever the
      // second one holds.
      if (line.getWidth(i) == 2) {
        i++;
      }
    }

    _paintBackgroundRun(
      canvas,
      offset,
      code: runCode,
      start: runStart,
      end: lineLength,
    );
  }

  /// One int for the color a cell's background paints: two cells with the same
  /// code paint the same color. An inverse cell paints its foreground, marked
  /// with [_inverseBackgroundBit]; a cell on the default background paints
  /// nothing.
  int _readBackgroundCode(BufferLine line, int index) {
    final isInverse = line.getAttributes(index) & CellFlags.inverse != 0;

    if (isInverse) {
      final inverseCode = line.getForeground(index) | _inverseBackgroundBit;

      return inverseCode;
    }

    final background = line.getBackground(index);
    final isDefaultBackground =
        background & CellColor.typeMask == CellColor.normal;

    if (isDefaultBackground) {
      return _noBackgroundCode;
    }

    return background;
  }

  /// Paints the cells from [start] up to [end] in the color [code] names.
  void _paintBackgroundRun(
    Canvas canvas,
    Offset offset, {
    required int code,
    required int start,
    required int end,
  }) {
    if (code == _noBackgroundCode) {
      return;
    }

    final isInverse = code & _inverseBackgroundBit != 0;
    final Color color;

    if (isInverse) {
      color = resolveForegroundColor(code & ~_inverseBackgroundBit);
    } else {
      color = resolveBackgroundColor(code);
    }

    final paint = Paint()..color = color;
    final left = offset.dx + start * _cellSize.width;

    // One pixel wider than the cells, as a single cell's rectangle always was,
    // so no seam shows where the next run's rectangle begins.
    final width = (end - start) * _cellSize.width + 1;
    final runRect = Rect.fromLTWH(left, offset.dy, width, _cellSize.height);

    canvas.drawRect(runRect, paint);
  }

  @pragma('vm:prefer-inline')
  void paintCell(Canvas canvas, Offset offset, CellData cellData) {
    paintCellBackground(canvas, offset, cellData);
    paintCellForeground(canvas, offset, cellData);
  }

  /// Paints the character in the cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellForeground(Canvas canvas, Offset offset, CellData cellData) {
    final charCode = cellData.content & CellContent.codepointMask;

    if (charCode == 0) {
      return;
    }

    // A space shows nothing but an underline: its paragraph carries no
    // background. Text has one between every two words, and each paragraph is a
    // draw call the raster thread still has to work through.
    final isBlankSpace =
        charCode == 0x20 && cellData.flags & CellFlags.underline == 0;

    if (isBlankSpace) {
      return;
    }

    final cacheKey = cellData.getHash() ^ _textScaler.hashCode;
    var paragraph = _paragraphCache.getLayoutFromCache(cacheKey);

    if (paragraph == null) {
      final cellFlags = cellData.flags;
      final style = _resolveCellTextStyle(cellData);

      // Flutter does not draw an underline below a space which is not between
      // other regular characters. As only single characters are drawn, this
      // will never produce an underline below a space in the terminal. As a
      // workaround the regular space CodePoint 0x20 is replaced with
      // the CodePoint 0xA0. This is a non breaking space and a underline can be
      // drawn below it.
      var char = String.fromCharCode(charCode);
      if (cellFlags & CellFlags.underline != 0 && charCode == 0x20) {
        char = String.fromCharCode(0xA0);
      }

      paragraph = _paragraphCache.performAndCacheLayout(
        char,
        style,
        _textScaler,
        cacheKey,
      );
    }

    canvas.drawParagraph(paragraph, offset);
  }

  /// The text style a cell's character draws in: its foreground color, or its
  /// background when inverse, at half alpha when faint; bold, italic and
  /// underline from its flags.
  TextStyle _resolveCellTextStyle(CellData cellData) {
    final cellFlags = cellData.flags;

    var color = cellFlags & CellFlags.inverse == 0
        ? resolveForegroundColor(cellData.foreground)
        : resolveBackgroundColor(cellData.background);

    if (cellFlags & CellFlags.faint != 0) {
      // 128 is round(255 * 0.5) — exactly what the deprecated withOpacity(0.5)
      // produced, so faint text keeps the shade it has always had.
      color = color.withAlpha(128);
    }

    final style = _textStyle.toTextStyle(
      color: color,
      bold: cellFlags & CellFlags.bold != 0,
      italic: cellFlags & CellFlags.italic != 0,
      underline: cellFlags & CellFlags.underline != 0,
    );

    return style;
  }

  /// Paints the background of a cell represented by [cellData] to [canvas] at
  /// [offset].
  @pragma('vm:prefer-inline')
  void paintCellBackground(Canvas canvas, Offset offset, CellData cellData) {
    late Color color;
    final colorType = cellData.background & CellColor.typeMask;

    if (cellData.flags & CellFlags.inverse != 0) {
      color = resolveForegroundColor(cellData.foreground);
    } else if (colorType == CellColor.normal) {
      return;
    } else {
      color = resolveBackgroundColor(cellData.background);
    }

    final paint = Paint()..color = color;
    final doubleWidth = cellData.content >> CellContent.widthShift == 2;
    final widthScale = doubleWidth ? 2 : 1;
    final size = Size(_cellSize.width * widthScale + 1, _cellSize.height);
    canvas.drawRect(offset & size, paint);
  }

  /// Get the effective foreground color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveForegroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.foreground;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }

  /// Get the effective background color for a cell from information encoded in
  /// [cellColor].
  @pragma('vm:prefer-inline')
  Color resolveBackgroundColor(int cellColor) {
    final colorType = cellColor & CellColor.typeMask;
    final colorValue = cellColor & CellColor.valueMask;

    switch (colorType) {
      case CellColor.normal:
        return _theme.background;
      case CellColor.named:
      case CellColor.palette:
        return _colorPalette[colorValue];
      case CellColor.rgb:
      default:
        return Color(colorValue | 0xFF000000);
    }
  }
}
