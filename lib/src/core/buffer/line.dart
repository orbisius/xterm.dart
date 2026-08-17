import 'dart:math' show min;
import 'dart:typed_data';

import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/cell.dart';
import 'package:xterm/src/core/cursor.dart';
import 'package:xterm/src/utils/circular_buffer.dart';
import 'package:xterm/src/utils/unicode_v11.dart';

const _cellSize = 4;

const _cellForeground = 0;

const _cellBackground = 1;

const _cellAttributes = 2;

const _cellContent = 3;

class BufferLine with IndexedItem {
  BufferLine(
    this._length, {
    this.isWrapped = false,
  }) : _data = Uint32List(_calcCapacity(_length) * _cellSize);

  int _length;

  Uint32List _data;

  Uint32List get data => _data;

  var isWrapped = false;

  int get length => _length;

  final _anchors = <CellAnchor>[];

  List<CellAnchor> get anchors => _anchors;

  int getForeground(int index) {
    return _data[index * _cellSize + _cellForeground];
  }

  int getBackground(int index) {
    return _data[index * _cellSize + _cellBackground];
  }

  int getAttributes(int index) {
    return _data[index * _cellSize + _cellAttributes];
  }

  int getContent(int index) {
    return _data[index * _cellSize + _cellContent];
  }

  int getCodePoint(int index) {
    return _data[index * _cellSize + _cellContent] & CellContent.codepointMask;
  }

  int getWidth(int index) {
    return _data[index * _cellSize + _cellContent] >> CellContent.widthShift;
  }

  void getCellData(int index, CellData cellData) {
    final offset = index * _cellSize;
    cellData.foreground = _data[offset + _cellForeground];
    cellData.background = _data[offset + _cellBackground];
    cellData.flags = _data[offset + _cellAttributes];
    cellData.content = _data[offset + _cellContent];
  }

  CellData createCellData(int index) {
    final cellData = CellData.empty();
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = cellData.foreground;
    _data[offset + _cellBackground] = cellData.background;
    _data[offset + _cellAttributes] = cellData.flags;
    _data[offset + _cellContent] = cellData.content;
    return cellData;
  }

  void setForeground(int index, int value) {
    _data[index * _cellSize + _cellForeground] = value;
  }

  void setBackground(int index, int value) {
    _data[index * _cellSize + _cellBackground] = value;
  }

  void setAttributes(int index, int value) {
    _data[index * _cellSize + _cellAttributes] = value;
  }

  void setContent(int index, int value) {
    _data[index * _cellSize + _cellContent] = value;
  }

  void setCodePoint(int index, int char) {
    final width = unicodeV11.wcwidth(char);
    setContent(index, char | (width << CellContent.widthShift));
  }

  void setCell(int index, int char, int witdh, CursorStyle style) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = style.foreground;
    _data[offset + _cellBackground] = style.background;
    _data[offset + _cellAttributes] = style.attrs;
    _data[offset + _cellContent] = char | (witdh << CellContent.widthShift);
  }

  void setCellData(int index, CellData cellData) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = cellData.foreground;
    _data[offset + _cellBackground] = cellData.background;
    _data[offset + _cellAttributes] = cellData.flags;
    _data[offset + _cellContent] = cellData.content;
  }

  void eraseCell(int index, CursorStyle style) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = style.foreground;
    _data[offset + _cellBackground] = style.background;
    _data[offset + _cellAttributes] = style.attrs;
    _data[offset + _cellContent] = 0;
  }

  void resetCell(int index) {
    final offset = index * _cellSize;
    _data[offset + _cellForeground] = 0;
    _data[offset + _cellBackground] = 0;
    _data[offset + _cellAttributes] = 0;
    _data[offset + _cellContent] = 0;
  }

  /// Blanks the whole line so it can be reused in place of a freshly allocated
  /// one, saving the [Uint32List] that a new [BufferLine] would allocate.
  ///
  /// Anchors are disposed rather than carried over: they refer to the content
  /// being discarded, and leaving them attached would silently repoint them at
  /// whatever is written next.
  void reset(int length) {
    while (_anchors.isNotEmpty) {
      _anchors.last.dispose();
    }

    resize(length);

    // The whole backing store, not just the first [length] cells: capacity is
    // rounded up past the line length, and [getTrimmedLength] reads to capacity
    // when it is called without a column count.
    _data.fillRange(0, _data.length, 0);

    isWrapped = false;
  }

  /// Erase cells whose index satisfies [start] <= index < [end]. Erased cells
  /// are filled with [style].
  void eraseRange(int start, int end, CursorStyle style) {
    // reset cell one to the left if start is second cell of a wide char
    if (start > 0 && getWidth(start - 1) == 2) {
      eraseCell(start - 1, style);
    }

    // reset cell one to the right if end is second cell of a wide char
    if (end < _length && getWidth(end - 1) == 2) {
      eraseCell(end - 1, style);
    }

    end = min(end, _length);
    for (var i = start; i < end; i++) {
      eraseCell(i, style);
    }
  }

  /// Remove [count] cells starting at [start]. Cells that are empty after the
  /// removal are filled with [style].
  void removeCells(int start, int count, [CursorStyle? style]) {
    assert(start >= 0 && start < _length);
    assert(count >= 0 && start + count <= _length);

    style ??= CursorStyle.empty;

    if (start + count < _length) {
      final moveStart = start * _cellSize;
      final moveEnd = (_length - count) * _cellSize;
      final moveOffset = count * _cellSize;
      for (var i = moveStart; i < moveEnd; i++) {
        _data[i] = _data[i + moveOffset];
      }
    }

    for (var i = _length - count; i < _length; i++) {
      eraseCell(i, style);
    }

    if (start > 0 && getWidth(start - 1) == 2) {
      eraseCell(start - 1, style);
    }

    // Update anchors, remove anchors that are inside the removed range.
    for (var i = 0; i < _anchors.length; i++) {
      final anchor = _anchors[i];
      if (anchor.x >= start) {
        if (anchor.x < start + count) {
          anchor.dispose();
        } else {
          anchor.reposition(anchor.x - count);
        }
      }
    }
  }

  /// Inserts [count] cells at [start]. New cells are initialized with [style].
  void insertCells(int start, int count, [CursorStyle? style]) {
    style ??= CursorStyle.empty;

    if (start > 0 && getWidth(start - 1) == 2) {
      eraseCell(start - 1, style);
    }

    if (start + count < _length) {
      final moveStart = start * _cellSize;
      final moveEnd = (_length - count) * _cellSize;
      final moveOffset = count * _cellSize;
      for (var i = moveEnd - 1; i >= moveStart; i--) {
        _data[i + moveOffset] = _data[i];
      }
    }

    final end = min(start + count, _length);
    for (var i = start; i < end; i++) {
      eraseCell(i, style);
    }

    if (getWidth(_length - 1) == 2) {
      eraseCell(_length - 1, style);
    }

    // Update anchors, move anchors that are after the inserted range.
    for (var i = 0; i < _anchors.length; i++) {
      final anchor = _anchors[i];
      if (anchor.x >= start + count) {
        anchor.reposition(anchor.x + count);

        // Remove anchors that are now outside the buffer.
        if (anchor.x >= _length) {
          anchor.dispose();
        }
      }
    }
  }

  void resize(int length) {
    assert(length >= 0);

    if (length == _length) {
      return;
    }

    if (length > _length) {
      final newBufferSize = _calcCapacity(length) * _cellSize;

      if (newBufferSize > _data.length) {
        final newBuffer = Uint32List(newBufferSize);
        newBuffer.setRange(0, _data.length, _data);
        _data = newBuffer;
      }
    }

    _length = length;

    for (var i = 0; i < _anchors.length; i++) {
      final anchor = _anchors[i];
      if (anchor.x > _length) {
        anchor.reposition(_length);
      }
    }
  }

  /// Returns the offset of the last cell that has content from the start of
  /// the line.
  int getTrimmedLength([int? cols]) {
    final maxCols = _data.length ~/ _cellSize;

    if (cols == null || cols > maxCols) {
      cols = maxCols;
    }

    if (cols <= 0) {
      return 0;
    }

    for (var i = cols - 1; i >= 0; i--) {
      var codePoint = getCodePoint(i);

      if (codePoint != 0) {
        // we are at the last cell in this line that has content.
        // the length of this line is the index of this cell + 1
        // the only exception is that if that last cell is wider
        // than 1 then we have to add the diff
        final lastCellWidth = getWidth(i);
        return i + lastCellWidth;
      }
    }
    return 0;
  }

  /// Copies [len] cells from [src] starting at [srcCol] to [dstCol] at this
  /// line.
  void copyFrom(BufferLine src, int srcCol, int dstCol, int len) {
    resize(dstCol + len);

    // data.setRange(
    //   dstCol * _cellSize,
    //   (dstCol + len) * _cellSize,
    //   Uint32List.sublistView(src.data, srcCol * _cellSize, len * _cellSize),
    // );

    var srcOffset = srcCol * _cellSize;
    var dstOffset = dstCol * _cellSize;

    for (var i = 0; i < len * _cellSize; i++) {
      _data[dstOffset++] = src._data[srcOffset++];
    }
  }

  static int _calcCapacity(int length) {
    assert(length >= 0);

    var capacity = 64;

    if (length < 256) {
      while (capacity < length) {
        capacity *= 2;
      }
    } else {
      capacity = 256;
      while (capacity < length) {
        capacity += 32;
      }
    }

    return capacity;
  }

  String getText([int? from, int? to]) {
    if (from == null || from < 0) {
      from = 0;
    }

    if (to == null || to > _length) {
      to = _length;
    }

    final builder = StringBuffer();

    // Blank cells are COUNTED, not written, and flushed only once a real
    // character follows. A run that turns out to be the row's unused tail is
    // therefore never flushed, so a line still copies without padding out to
    // the terminal's width — and it takes one pass to do both, with no second
    // scan to locate where the content ends.
    var pendingBlanks = 0;

    // Carried rather than re-read: spotting a wide character's second cell
    // needs the PREVIOUS cell's width, and this is a hot path — getText walks
    // every cell of a scrollback that can run to tens of thousands of lines.
    var previousWidth = from > 0 ? getWidth(from - 1) : 0;

    for (var i = from; i < to; i++) {
      final codePoint = getCodePoint(i);
      final width = getWidth(i);

      // The SECOND half of a wide character (an emoji, a CJK glyph) reads as 0
      // because one code point spans two cells. It is not a gap and adds
      // nothing — the character was already emitted from the cell before it.
      final isWideCharTail = previousWidth == 2;

      previousWidth = width;

      if (isWideCharTail) {
        continue;
      }

      // A cell that was never written reads as 0 as well, and DISPLAYS as a
      // blank, so between two written cells it has to copy as one: full-screen
      // programs lay out by MOVING THE CURSOR rather than writing padding
      // spaces, which leaves untouched cells sitting between the words.
      // Dropping them closes the gap and silently rewrites the text —
      // "cmd -r123" comes back as "cmd-r123", a different command.
      if (codePoint == 0) {
        pendingBlanks++;

        continue;
      }

      if (i + width <= to) {
        if (pendingBlanks > 0) {
          builder.write(' ' * pendingBlanks);

          pendingBlanks = 0;
        }

        builder.writeCharCode(codePoint);
      }
    }

    final text = builder.toString();

    return text;
  }

  CellAnchor createAnchor(int offset) {
    final anchor = CellAnchor(offset, owner: this);
    _anchors.add(anchor);
    return anchor;
  }

  void dispose() {
    for (final anchor in _anchors) {
      anchor.dispose();
    }
  }

  @override
  String toString() {
    return getText();
  }
}

/// A handle to a cell in a [BufferLine] that can be used to track the location
/// of the cell. Anchors are guaranteed to be stable, retaining their relative
/// position to each other after mutations to the buffer.
class CellAnchor {
  CellAnchor(int offset, {BufferLine? owner})
      : _offset = offset,
        _owner = owner;

  int _offset;

  int get x {
    return _offset;
  }

  int get y {
    assert(attached);
    return _owner!.index;
  }

  CellOffset get offset {
    assert(attached);
    return CellOffset(_offset, _owner!.index);
  }

  BufferLine? _owner;

  BufferLine? get line => _owner;

  bool get attached => _owner?.attached ?? false;

  void reparent(BufferLine owner, int offset) {
    _owner?._anchors.remove(this);
    _owner = owner;
    _owner?._anchors.add(this);
    _offset = offset;
  }

  void reposition(int offset) {
    _offset = offset;
  }

  void dispose() {
    _owner?._anchors.remove(this);
    _owner = null;
  }

  @override
  String toString() {
    if (attached) {
      return 'CellAnchor($x, $y)';
    } else {
      return 'CellAnchor($x, detached)';
    }
  }
}
