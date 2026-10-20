import 'package:flutter/widgets.dart';
import 'package:xterm/core.dart';
import 'package:xterm/src/ui/alt_screen_wheel_fallback.dart';
import 'package:xterm/src/ui/infinite_scroll_view.dart';

/// Handles scrolling gestures in the alternate screen buffer. In alternate
/// screen buffer, the terminal don't have a scrollback buffer, instead, the
/// scroll gestures are converted to escape sequences based on the current
/// report mode declared by the application.
class TerminalScrollGestureHandler extends StatefulWidget {
  const TerminalScrollGestureHandler({
    super.key,
    required this.terminal,
    required this.getCellOffset,
    required this.getLineHeight,
    this.simulateScroll = true,
    this.altScreenWheelFallback = AltScreenWheelFallback.scrollHistory,
    required this.child,
  });

  final Terminal terminal;

  /// Returns the cell offset for the pixel offset.
  /// The cell under a GLOBAL pointer position. Global because that is all this
  /// handler has — it sits above the terminal in the tree — so the callback owns
  /// the conversion, since only the terminal knows where it sits on screen.
  final CellOffset Function(Offset globalOffset) getCellOffset;

  /// Returns the pixel height of lines in the terminal.
  final double Function() getLineHeight;

  /// Whether to simulate scroll events in the terminal when the application
  /// doesn't declare it supports mouse wheel events. true by default as it
  /// is the default behavior of most terminals.
  final bool simulateScroll;

  /// Where the wheel goes on the alternate screen when the program did not ask
  /// for it.
  final AltScreenWheelFallback altScreenWheelFallback;

  /// The most lines one scroll callback may turn into events.
  ///
  /// macOS hands ACCELERATED wheel deltas — a fast spin arrives as one event
  /// carrying hundreds of pixels — and an event per line crossed turned that
  /// into pages of travel the program executes with nothing to take it back
  /// (measured: a 600 px spin sent 37 reports, about two pages). Physical
  /// terminals quantize a notch to a few lines; two notches' worth per event
  /// keeps a fast spin fast without becoming a leap. The excess is DROPPED,
  /// never queued — queued lines would keep arriving after the wheel stopped,
  /// which is the same runaway wearing a delay.
  static const int maxLinesPerScrollEvent = 6;

  final Widget child;

  @override
  State<TerminalScrollGestureHandler> createState() =>
      _TerminalScrollGestureHandlerState();
}

class _TerminalScrollGestureHandlerState
    extends State<TerminalScrollGestureHandler> {
  /// Whether the wheel goes to the program instead of moving the view — see
  /// [_resolveProgramOwnsWheel]. While false this widget does nothing.
  var programOwnsWheel = false;

  /// The variable that tracks the line offset in last scroll event. Used to
  /// determine how many the scroll events should be sent to the terminal.
  var lastLineOffset = 0;

  /// Where the last scroll gesture started, in GLOBAL coordinates — that is what
  /// [PointerEvent.position] is, and this handler sits above the terminal in the
  /// tree, so it has no terminal-local coordinates to record. Named for its
  /// space because [getCellOffset] takes the other one, and nothing about
  /// `Offset` says which you are holding.
  var lastGlobalPointerPosition = Offset.zero;

  @override
  void initState() {
    widget.terminal.addListener(_onTerminalUpdated);
    programOwnsWheel = _resolveProgramOwnsWheel();
    super.initState();
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalUpdated);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TerminalScrollGestureHandler oldWidget) {
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_onTerminalUpdated);
      widget.terminal.addListener(_onTerminalUpdated);
    }

    _takeWheelOwnership();

    super.didUpdateWidget(oldWidget);
  }

  void _onTerminalUpdated() {
    final ownsWheel = _resolveProgramOwnsWheel();

    if (ownsWheel == programOwnsWheel) {
      return;
    }

    setState(_takeWheelOwnership);
  }

  /// Re-reads who owns the wheel. The count of lines already sent starts over,
  /// because the scroll view that counted them is built afresh.
  void _takeWheelOwnership() {
    programOwnsWheel = _resolveProgramOwnsWheel();
    lastLineOffset = 0;
  }

  /// Whether the wheel goes to the program: never on the main screen; on the
  /// alternate screen when the program asked for it — mouse reporting or
  /// DECSET 1007 — or when the host sends it there regardless.
  bool _resolveProgramOwnsWheel() {
    final terminal = widget.terminal;

    if (!terminal.isUsingAltBuffer) {
      return false;
    }

    final fallback = widget.altScreenWheelFallback;

    if (fallback == AltScreenWheelFallback.sendToProgram) {
      return true;
    }

    final programAskedForWheel =
        terminal.mouseMode.reportScroll || terminal.altBufferMouseScrollMode;

    return programAskedForWheel;
  }

  /// Send a single scroll event to the terminal. If [simulateScroll] is true,
  /// then if the application doesn't recognize mouse wheel events, this method
  /// will simulate scroll events by sending up/down arrow keys.
  void _sendScrollEvent(bool up) {
    final position = widget.getCellOffset(lastGlobalPointerPosition);

    final handled = widget.terminal.mouseInput(
      up ? TerminalMouseButton.wheelUp : TerminalMouseButton.wheelDown,
      TerminalMouseButtonState.down,
      position,
    );

    if (!handled && widget.simulateScroll) {
      widget.terminal.keyInput(
        up ? TerminalKey.arrowUp : TerminalKey.arrowDown,
      );
    }
  }

  void _onScroll(double offset) {
    final currentLineOffset = offset ~/ widget.getLineHeight();

    final delta = currentLineOffset - lastLineOffset;

    // See [TerminalScrollGestureHandler.maxLinesPerScrollEvent] — the excess
    // of an accelerated delta is dropped, and setting [lastLineOffset] to the
    // CURRENT offset below is what drops it rather than queueing it.
    var sendCount = delta.abs();

    if (sendCount > TerminalScrollGestureHandler.maxLinesPerScrollEvent) {
      sendCount = TerminalScrollGestureHandler.maxLinesPerScrollEvent;
    }

    for (var i = 0; i < sendCount; i++) {
      _sendScrollEvent(delta < 0);
    }

    lastLineOffset = currentLineOffset;
  }

  void _recordPointerPosition(PointerEvent event) {
    lastGlobalPointerPosition = event.position;
  }

  @override
  Widget build(BuildContext context) {
    if (!programOwnsWheel) {
      return widget.child;
    }

    // The view below must decline the wheel: with history to scroll, it is
    // offered each notch first and would take it before this handler sees it.
    // A copy keeps every other setting the host gave scrolling.
    final scrollBehavior = ScrollConfiguration.of(context);
    final wheelDecliningBehavior = scrollBehavior.copyWith(
      physics: const NeverScrollableScrollPhysics(),
    );

    final wheelDecliningChild = ScrollConfiguration(
      behavior: wheelDecliningBehavior,
      child: widget.child,
    );

    final wheelForProgram = InfiniteScrollView(
      onScroll: _onScroll,
      child: wheelDecliningChild,
    );

    final pointerTrackingView = Listener(
      onPointerSignal: _recordPointerPosition,
      onPointerDown: _recordPointerPosition,
      child: wheelForProgram,
    );

    return pointerTrackingView;
  }
}
