import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  DragStartDetails? _lastDragStartDetails;

  LongPressStartDetails? _lastLongPressStartDetails;

  /// The cell where the program last saw the primary button held: set when
  /// the program takes a press, moved by motion, cleared by the release.
  /// While it is set the pointer belongs to the program, so a drag, a double
  /// click or a long press selects nothing; while it is null they select.
  CellOffset? _heldButtonCell;

  @override
  Widget build(BuildContext context) {
    final gestureDetector = TerminalGestureDetector(
      child: widget.child,
      onTapUp: widget.onTapUp,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onSecondaryTapDown,
      onTertiaryTapUp: onSecondaryTapUp,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onLongPressUp: onLongPressUp,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDoubleTapDown: onDoubleTapDown,
      onDoubleTapUp: onDoubleTapUp,
    );

    return gestureDetector;
  }

  /// Whether [input] from this view goes to the program: the view is not
  /// read-only, the host hands that input over, and Shift is not held — Shift
  /// keeps the mouse with the terminal's own selection, as in xterm.
  bool _shouldSendPointerInput(PointerInput input) {
    if (widget.readOnly) {
      return false;
    }

    final isHandedOver = widget.terminalController.shouldSendPointerInput(
      input,
    );

    if (!isHandedOver) {
      return false;
    }

    final isShiftHeld = HardwareKeyboard.instance.isShiftPressed;

    return !isShiftHeld;
  }

  bool _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendPointerInput(PointerInput.tap)) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }

    return handled;
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendPointerInput(PointerInput.tap)) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    final handled = _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );

    // A new press starts over, so a cell left by an earlier gesture is stale.
    _heldButtonCell =
        handled ? renderTerminal.getCellOffset(details.localPosition) : null;
  }

  void onSingleTapUp(TapUpDetails details) {
    if (_heldButtonCell == null) {
      widget.onSingleTapUp?.call(details);

      return;
    }

    _releaseHeldButton();
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    // The program took this press, so the word under it is the program's to
    // select.
    if (_heldButtonCell != null) {
      return;
    }

    renderTerminal.selectWord(details.localPosition);
  }

  void onDoubleTapUp(TapUpDetails details) {
    _releaseHeldButton();
  }

  void onLongPressStart(LongPressStartDetails details) {
    _lastLongPressStartDetails = details;

    if (_heldButtonCell != null) {
      return;
    }

    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_heldButtonCell != null) {
      return;
    }

    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  void onLongPressUp() {
    _releaseHeldButton();
  }

  void onDragStart(DragStartDetails details) {
    _lastDragStartDetails = details;

    final isProgramDrag = _startDragInProgram(details.localPosition);

    if (isProgramDrag) {
      return;
    }

    details.kind == PointerDeviceKind.mouse
        ? renderTerminal.selectCharacters(details.localPosition)
        : renderTerminal.selectWord(details.localPosition);
  }

  void onDragUpdate(DragUpdateDetails details) {
    final heldButtonCell = _heldButtonCell;

    if (heldButtonCell != null) {
      final cell = renderTerminal.getCellOffset(details.localPosition);

      // A program is told about cells, so a move inside one says nothing new.
      if (cell != heldButtonCell) {
        _reportPrimaryButton(
          state: TerminalMouseButtonState.down,
          cell: cell,
          isMotion: true,
        );

        _heldButtonCell = cell;
      }

      return;
    }

    renderTerminal.selectCharacters(
      _lastDragStartDetails!.localPosition,
      details.localPosition,
    );
  }

  void onDragEnd(DragEndDetails details) {
    _releaseHeldButton();
  }

  /// Whether the drag starting at [position] goes to the program, reporting
  /// its press unless the tap already did. When the host does not hand drags
  /// over, a press the tap already reported is released here, so the program
  /// is not left holding a button while the terminal selects.
  bool _startDragInProgram(Offset position) {
    if (!_shouldSendPointerInput(PointerInput.drag)) {
      _releaseHeldButton();

      return false;
    }

    if (_heldButtonCell != null) {
      return true;
    }

    final pressCell = renderTerminal.getCellOffset(position);

    final isTaken = _reportPrimaryButton(
      state: TerminalMouseButtonState.down,
      cell: pressCell,
    );

    if (isTaken) {
      _heldButtonCell = pressCell;

      final controller = widget.terminalController;

      // The press went to the program, so the terminal's selection, if any,
      // ends here.
      if (controller.selection != null) {
        controller.clearSelection();
      }
    }

    return isTaken;
  }

  /// Reports the primary button to the program at [cell]. Returns whether the
  /// program's mouse mode asked for this report.
  bool _reportPrimaryButton({
    required TerminalMouseButtonState state,
    required CellOffset cell,
    bool isMotion = false,
  }) {
    final terminal = terminalView.widget.terminal;

    final isReported = terminal.mouseInput(
      TerminalMouseButton.left,
      state,
      cell,
      isMotion: isMotion,
    );

    return isReported;
  }

  /// Reports the primary button coming up where the program last saw it,
  /// when the program holds it.
  void _releaseHeldButton() {
    final heldButtonCell = _heldButtonCell;

    if (heldButtonCell == null) {
      return;
    }

    _reportPrimaryButton(
      state: TerminalMouseButtonState.up,
      cell: heldButtonCell,
    );

    _heldButtonCell = null;
  }
}
