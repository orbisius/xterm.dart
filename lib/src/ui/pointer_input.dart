enum PointerInput {
  /// Taps / buttons presses & releases.
  tap,

  /// Scroll / mouse wheels events.
  scroll,

  /// Drag events, a pointer is in a down state and dragged across the terminal.
  drag,

  /// Move events, a pointer is in an up state and moved across the terminal.
  move,

  /// Repeat taps, a tap within the double-tap time and distance of the last
  /// one: the second click of a double click, the second and third of a
  /// triple click. Left out, they stay with the terminal as when no program
  /// asked for the mouse, so a double click selects a word while its first
  /// click still reaches the program as a [tap].
  repeatTap,
}

class PointerInputs {
  final Set<PointerInput> inputs;

  const PointerInputs(this.inputs);

  const PointerInputs.none() : inputs = const <PointerInput>{};

  const PointerInputs.all()
      : inputs = const <PointerInput>{
          PointerInput.tap,
          PointerInput.scroll,
          PointerInput.drag,
          PointerInput.move,
          PointerInput.repeatTap,
        };
}
