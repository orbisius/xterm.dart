import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/ui/custom_text_edit.dart';

/// Records what [CustomTextEdit] reports, so a test can assert on the exact
/// sequence of inserts rather than on rendered text.
class InputLog {
  final inserts = <String>[];

  final composingTexts = <String?>[];

  var deleteCount = 0;

  void onInsert(String text) => inserts.add(text);

  void onComposing(String? text) => composingTexts.add(text);

  void onDelete() => deleteCount++;
}

/// Mounts a [CustomTextEdit] with a live input connection and returns its state,
/// which is what the tests drive through the platform channel.
Future<CustomTextEditState> showEditor(
  WidgetTester tester, {
  required InputLog log,
  bool deleteDetection = false,
}) async {
  final stateKey = GlobalKey<CustomTextEditState>();

  final editor = CustomTextEdit(
    key: stateKey,
    focusNode: FocusNode(),
    autofocus: true,
    deleteDetection: deleteDetection,
    onInsert: log.onInsert,
    onDelete: log.onDelete,
    onComposing: log.onComposing,
    onAction: (_) {},
    onKeyEvent: (_, __) => KeyEventResult.ignored,
    child: const SizedBox(width: 100, height: 100),
  );

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: editor)));

  await tester.pump();

  final state = stateKey.currentState;

  if (state == null) {
    fail('CustomTextEdit did not mount');
  }

  // Attaches the TextInputClient. Without it there is no connection to reset,
  // and every assertion below would be measuring a different situation.
  state.requestKeyboard();

  await tester.pump();

  expect(
    state.hasInputConnection,
    isTrue,
    reason: 'the assertions that follow are vacuous with no connection open',
  );

  return state;
}

void main() {
  group('CustomTextEdit insert delta', () {
    // THE REGRESSION. `updateEditingValue` asks the platform to clear the field
    // after every insert, but that request is applied asynchronously. A key
    // committed before it lands is reported on top of text that was already
    // sent — 's' then 'st' — and measuring the delta from offset 0 sent that 's'
    // a second time, so typing "stuff" produced "sstuff".
    testWidgets('a key beating the reset inserts only the new text', (
      tester,
    ) async {
      final log = InputLog();

      await showEditor(tester, log: log);

      tester.testTextInput.enterText('s');

      await tester.pump();

      expect(log.inserts, ['s']);

      // The platform has not applied the reset, so it still holds the 's'.
      tester.testTextInput.enterText('st');

      await tester.pump();

      expect(log.inserts, ['s', 't']);
    });

    testWidgets('the ordinary sequence inserts once per key', (tester) async {
      final log = InputLog();

      await showEditor(tester, log: log);

      tester.testTextInput.enterText('s');

      await tester.pump();

      // The reset landed, so the next commit starts from an empty field.
      tester.testTextInput.enterText('t');

      await tester.pump();

      expect(log.inserts, ['s', 't']);
    });

    testWidgets('a preedit reports composing and inserts nothing', (
      tester,
    ) async {
      final log = InputLog();

      await showEditor(tester, log: log);

      // What a dead key produces: a preedit with a live composing range.
      const preedit = TextEditingValue(
        text: '´',
        selection: TextSelection.collapsed(offset: 1),
        composing: TextRange(start: 0, end: 1),
      );

      tester.testTextInput.updateEditingValue(preedit);

      await tester.pump();

      expect(log.composingTexts, ['´']);
      expect(log.inserts, isEmpty);

      tester.testTextInput.enterText('é');

      await tester.pump();

      expect(log.inserts, ['é']);
    });

    testWidgets('a dead key beating the reset inserts once', (tester) async {
      final log = InputLog();

      await showEditor(tester, log: log);

      tester.testTextInput.enterText('a');

      await tester.pump();

      expect(log.inserts, ['a']);

      // The reset has not landed, so the preedit sits on top of the 'a'.
      const preedit = TextEditingValue(
        text: 'a´',
        selection: TextSelection.collapsed(offset: 2),
        composing: TextRange(start: 1, end: 2),
      );

      tester.testTextInput.updateEditingValue(preedit);

      await tester.pump();

      expect(log.inserts, ['a']);

      tester.testTextInput.enterText('aá');

      await tester.pump();

      expect(log.inserts, ['a', 'á']);
    });

    testWidgets('a delete does not shift the next insert', (tester) async {
      final log = InputLog();

      await showEditor(tester, log: log, deleteDetection: true);

      // The base is two spaces, so one space is the backspace signal.
      tester.testTextInput.enterText(' ');

      await tester.pump();

      expect(log.deleteCount, 1);
      expect(log.inserts, isEmpty);

      // The consumed text is now SHORTER than the base, which is what keeps the
      // next value read as a fresh field rather than an extension of it.
      tester.testTextInput.enterText('  x');

      await tester.pump();

      expect(log.inserts, ['x']);
    });
  });
}
