import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

class TerminalGestureDetector extends StatefulWidget {
  const TerminalGestureDetector({
    super.key,
    this.child,
    this.onSingleTapUp,
    this.onTapUp,
    this.onTapDown,
    this.onRepeatTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressUp,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onDoubleTapDown,
    this.onDoubleTapUp,
  });

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  /// The first press of a run of clicks; a press that repeats a click goes to
  /// [onRepeatTapDown] instead.
  final GestureTapDownCallback? onTapDown;

  /// A press within [kDoubleTapTimeout] and [kDoubleTapSlop] of the last
  /// click's release: the second press of a double click, and each press after
  /// it in the same run.
  final GestureTapDownCallback? onRepeatTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onDoubleTapDown;

  /// The second click of a double click coming up — [onSingleTapUp] fires for
  /// the first click only.
  final GestureTapUpCallback? onDoubleTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final GestureLongPressStartCallback? onLongPressStart;

  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;

  final GestureLongPressUpCallback? onLongPressUp;

  final GestureDragStartCallback? onDragStart;

  final GestureDragUpdateCallback? onDragUpdate;

  /// Fires when the button comes up and the drag is over.
  final GestureDragEndCallback? onDragEnd;

  @override
  State<TerminalGestureDetector> createState() =>
      _TerminalGestureDetectorState();
}

class _TerminalGestureDetectorState extends State<TerminalGestureDetector> {
  Timer? _doubleTapTimer;

  Offset? _lastTapOffset;

  // True if a second tap down of a double tap is detected. Used to discard
  // subsequent tap up / tap hold of the same tap.
  bool _isDoubleTap = false;

  // True if the last tap up ended a double tap. A press in the window it opens
  // repeats the click without making a second double tap.
  bool _isLastTapDouble = false;

  @override
  void dispose() {
    _doubleTapTimer?.cancel();
    super.dispose();
  }

  // The down handler is force-run on success of a single tap and optimistically
  // run before a long press success.
  void _handleTapDown(TapDownDetails details) {
    final isRepeatTap = _doubleTapTimer != null &&
        _isWithinDoubleTapTolerance(details.globalPosition);

    if (isRepeatTap) {
      widget.onRepeatTapDown?.call(details);
    } else {
      widget.onTapDown?.call(details);
    }

    // If there was already a previous tap, the second down hold/tap is a
    // double tap down; the press after a double tap only carries its run on.
    if (isRepeatTap && !_isLastTapDouble) {
      widget.onDoubleTapDown?.call(details);

      _isDoubleTap = true;
    }

    // Every press closes the window, so a timer left by an earlier click can
    // never close the one this click's release opens.
    _doubleTapTimer?.cancel();
    _doubleTapTimeout();
  }

  void _handleTapUp(TapUpDetails details) {
    if (_isDoubleTap) {
      widget.onDoubleTapUp?.call(details);
    } else {
      widget.onSingleTapUp?.call(details);
    }

    _isLastTapDouble = _isDoubleTap;
    _isDoubleTap = false;

    // A double tap's release opens the window too, so a click after a double
    // click still repeats it.
    _lastTapOffset = details.globalPosition;
    _doubleTapTimer = Timer(kDoubleTapTimeout, _doubleTapTimeout);
  }

  void _doubleTapTimeout() {
    _doubleTapTimer = null;
    _lastTapOffset = null;
  }

  bool _isWithinDoubleTapTolerance(Offset secondTapOffset) {
    if (_lastTapOffset == null) {
      return false;
    }

    final Offset difference = secondTapOffset - _lastTapOffset!;
    return difference.distance <= kDoubleTapSlop;
  }

  @override
  Widget build(BuildContext context) {
    final gestures = <Type, GestureRecognizerFactory>{};

    gestures[TapGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
      () => TapGestureRecognizer(debugOwner: this),
      (TapGestureRecognizer instance) {
        instance
          ..onTapDown = _handleTapDown
          ..onTapUp = _handleTapUp
          ..onSecondaryTapDown = widget.onSecondaryTapDown
          ..onSecondaryTapUp = widget.onSecondaryTapUp
          ..onTertiaryTapDown = widget.onTertiaryTapDown
          ..onTertiaryTapUp = widget.onTertiaryTapUp;
      },
    );

    gestures[LongPressGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
      () => LongPressGestureRecognizer(
        debugOwner: this,
        supportedDevices: {
          PointerDeviceKind.touch,
          // PointerDeviceKind.mouse, // for debugging purposes only
        },
      ),
      (LongPressGestureRecognizer instance) {
        instance
          ..onLongPressStart = widget.onLongPressStart
          ..onLongPressMoveUpdate = widget.onLongPressMoveUpdate
          ..onLongPressUp = widget.onLongPressUp;
      },
    );

    gestures[PanGestureRecognizer] =
        GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
      () => PanGestureRecognizer(
        debugOwner: this,
        supportedDevices: <PointerDeviceKind>{PointerDeviceKind.mouse},
      ),
      (PanGestureRecognizer instance) {
        instance
          ..dragStartBehavior = DragStartBehavior.down
          ..onStart = widget.onDragStart
          ..onUpdate = widget.onDragUpdate
          ..onEnd = widget.onDragEnd;
      },
    );

    final gestureDetector = RawGestureDetector(
      gestures: gestures,
      excludeFromSemantics: true,
      child: widget.child,
    );

    return gestureDetector;
  }
}
