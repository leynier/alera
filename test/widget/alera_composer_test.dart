import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Enter sends while Shift+Enter inserts a line break', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    var sends = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraComposer(
            controller: controller,
            focusNode: focusNode,
            onSend: () => sends += 1,
            onClose: () {},
            textActions: const <AleraTextActionMenuItem>[],
            onTextActionSelected: (_) {},
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Prompt');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(controller.text, 'Prompt\n');
    expect(sends, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sends, 1);
  });

  testWidgets(
    'configured Text Actions are available for selected prompt text',
    (tester) async {
      final controller = TextEditingController(text: 'Improve this');
      final focusNode = FocusNode();
      String? selectedAction;
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AleraComposer(
              controller: controller,
              focusNode: focusNode,
              onSend: () {},
              onClose: () {},
              textActions: const <AleraTextActionMenuItem>[
                AleraTextActionMenuItem(id: 'concise', label: 'Make Concise'),
              ],
              onTextActionSelected: (id) => selectedAction = id,
            ),
          ),
        ),
      );

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 7,
      );
      await tester.pump();
      await tester.tap(find.text('Text Actions'));
      await tester.pumpAndSettle();

      expect(find.text('Select Text Action'), findsOneWidget);
      expect(find.text('Make Concise'), findsOneWidget);
      await tester.tap(find.text('Make Concise'));
      await tester.pumpAndSettle();

      expect(selectedAction, 'concise');
    },
  );
}
