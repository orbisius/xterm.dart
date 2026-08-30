import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets(
    'getCellOffset clamps a non-finite offset to the origin instead of throwing',
    (tester) async {
      final terminal = Terminal();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: TerminalView(terminal),
        ),
      ));

      final state = tester.state<TerminalViewState>(find.byType(TerminalView));
      final renderTerminal = state.renderTerminal;

      // A degenerate ancestor transform (a display reconfigured under a
      // running window) turns converted coordinates into NaN or infinity;
      // `~/` throws on both, killing the gesture that asked.
      final nanCell = renderTerminal.getCellOffset(
        const Offset(double.nan, double.nan),
      );

      expect(nanCell, const CellOffset(0, 0));

      final infiniteCell = renderTerminal.getCellOffset(
        const Offset(double.infinity, double.negativeInfinity),
      );

      expect(infiniteCell, const CellOffset(0, 0));

      // A finite offset keeps resolving normally beside the guard.
      final originCell = renderTerminal.getCellOffset(Offset.zero);

      expect(originCell, const CellOffset(0, 0));
    },
  );
}
