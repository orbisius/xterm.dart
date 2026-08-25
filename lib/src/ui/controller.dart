import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:xterm/src/base/disposable.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/buffer/range.dart';
import 'package:xterm/src/core/buffer/range_block.dart';
import 'package:xterm/src/core/buffer/range_line.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/selection_mode.dart';

class TerminalController with ChangeNotifier {
  TerminalController({
    SelectionMode selectionMode = SelectionMode.line,
    PointerInputs pointerInputs = const PointerInputs({PointerInput.tap}),
    bool suspendPointerInput = false,
  })  : _selectionMode = selectionMode,
        _pointerInputs = pointerInputs,
        _suspendPointerInputs = suspendPointerInput;

  CellAnchor? _selectionBase;
  CellAnchor? _selectionExtent;

  SelectionMode get selectionMode => _selectionMode;
  SelectionMode _selectionMode;

  /// The set of pointer events which will be used as mouse input for the terminal.
  PointerInputs get pointerInput => _pointerInputs;
  PointerInputs _pointerInputs;

  /// True if sending pointer events to the terminal is suspended.
  bool get suspendedPointerInputs => _suspendPointerInputs;
  bool _suspendPointerInputs;

  List<TerminalHighlight> get highlights => _highlights;
  final _highlights = <TerminalHighlight>[];

  BufferRange? get selection {
    final base = _selectionBase;
    final extent = _selectionExtent;

    if (base == null || extent == null) {
      return null;
    }

    if (!base.attached || !extent.attached) {
      return null;
    }

    return _createRange(base.offset, extent.offset);
  }

  /// Set selection on the terminal from [base] to [extent]. This method takes
  /// the ownership of [base] and [extent] and will dispose them when the
  /// selection is cleared or changed.
  void setSelection(CellAnchor base, CellAnchor extent, {SelectionMode? mode}) {
    _selectionBase?.dispose();
    _selectionBase = base;

    _selectionExtent?.dispose();
    _selectionExtent = extent;

    if (mode != null) {
      _selectionMode = mode;
    }

    notifyListeners();
  }

  BufferRange _createRange(CellOffset begin, CellOffset end) {
    switch (selectionMode) {
      case SelectionMode.line:
        return BufferRangeLine(begin, end);
      case SelectionMode.block:
        return BufferRangeBlock(begin, end);
    }
  }

  /// Whether the selection is DRAWN. True by default; the selection itself is
  /// unaffected either way.
  ///
  /// A host needs this on the alternate screen, where a full-screen program
  /// repaints the rows a selection covers instead of scrolling them. The
  /// selection is still there and still copyable, but the highlight now sits over
  /// characters the user never chose — so the host hides it until the rows hold
  /// that text again, rather than clearing a selection the user still wants.
  bool get selectionVisible => _selectionVisible;
  bool _selectionVisible = true;

  /// Shows or hides the selection highlight without touching the selection.
  void setSelectionVisible(bool visible) {
    if (_selectionVisible == visible) {
      return;
    }

    _selectionVisible = visible;
    notifyListeners();
  }

  /// Controls how the terminal behaves when the user selects a range of text.
  /// The default is [SelectionMode.line]. Setting this to [SelectionMode.block]
  /// enables block selection mode.
  void setSelectionMode(SelectionMode newSelectionMode) {
    // If the new mode is the same as the old mode,
    // nothing has to be changed.
    if (_selectionMode == newSelectionMode) {
      return;
    }
    // Set the new mode.
    _selectionMode = newSelectionMode;
    notifyListeners();
  }

  /// Clears the current selection.
  void clearSelection() {
    _selectionBase?.dispose();
    _selectionBase = null;
    _selectionExtent?.dispose();
    _selectionExtent = null;
    notifyListeners();
  }

  // Select which type of pointer events are send to the terminal.
  void setPointerInputs(PointerInputs pointerInput) {
    _pointerInputs = pointerInput;
    notifyListeners();
  }

  // Toggle sending pointer events to the terminal.
  void setSuspendPointerInput(bool suspend) {
    _suspendPointerInputs = suspend;
    notifyListeners();
  }

  // Returns true if this type of PointerInput should be send to the Terminal.
  @internal
  bool shouldSendPointerInput(PointerInput pointerInput) {
    // Always return false if pointer input is suspended.
    return _suspendPointerInputs
        ? false
        : _pointerInputs.inputs.contains(pointerInput);
  }

  /// Creates a new highlight on the terminal from [p1] to [p2] with the given
  /// [color]. The highlight will be removed when the returned object is
  /// disposed.
  TerminalHighlight highlight({
    required CellAnchor p1,
    required CellAnchor p2,
    required Color color,
  }) {
    final highlight = TerminalHighlight(
      this,
      p1: p1,
      p2: p2,
      color: color,
    );

    _highlights.add(highlight);
    notifyListeners();

    highlight.registerCallback(() {
      _highlights.remove(highlight);
      notifyListeners();
    });

    return highlight;
  }
}

class TerminalHighlight with Disposable {
  final TerminalController owner;

  final CellAnchor p1;

  final CellAnchor p2;

  final Color color;

  TerminalHighlight(
    this.owner, {
    required this.p1,
    required this.p2,
    required this.color,
  });

  /// Returns the range of the highlight. May be null if the anchors that
  /// define the highlight are not attached to the terminal.
  BufferRange? get range {
    if (!p1.attached || !p2.attached) {
      return null;
    }
    return BufferRangeLine(p1.offset, p2.offset);
  }

  /// Releases the anchors along with the highlight.
  ///
  /// An anchor registers itself with the line it points at and is only taken off
  /// again when it is disposed or that line leaves the buffer. Dropping the
  /// highlight without them left both anchors attached for as long as their
  /// lines lived, and every buffer operation that moves a line walks the anchors
  /// on it — so repeated highlighting (a search re-run on every keystroke) both
  /// grew memory and made scrolling steadily more expensive. On the alternate
  /// screen, where lines are never evicted, nothing ever cleaned them up.
  ///
  /// [TerminalController.clearSelection] already disposes the anchors it was
  /// given, so a highlight owning the two it holds matches how a selection
  /// behaves rather than introducing a second rule.
  @override
  void dispose() {
    p1.dispose();
    p2.dispose();
    super.dispose();
  }
}
