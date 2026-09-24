import 'package:alera/src/design_system/forms/alera_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Control+Enter submits while Enter does not', (tester) async {
    var submits = 0;
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraTextField(
            controller: controller,
            labelText: 'Initial Prompt',
            minLines: 4,
            maxLines: 8,
            onCommandEnter: () => submits += 1,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Build it');
    expect(await tester.sendKeyEvent(.enter), isFalse);
    await tester.pump();
    expect(submits, 0);

    await tester.sendKeyDownEvent(.controlLeft);
    expect(await tester.sendKeyEvent(.enter), isTrue);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pump();
    expect(submits, 1);
  });

  testWidgets('Cmd+Enter submits the field', (tester) async {
    var submits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraTextField(
            labelText: 'Initial Prompt',
            minLines: 4,
            maxLines: 8,
            onCommandEnter: () => submits += 1,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Build it');
    await tester.sendKeyDownEvent(.metaLeft);
    expect(await tester.sendKeyEvent(.enter), isTrue);
    await tester.sendKeyUpEvent(.metaLeft);
    await tester.pump();
    expect(submits, 1);
  });

  testWidgets('key-repeat Control+Enter submits once', (tester) async {
    var submits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraTextField(
            labelText: 'Initial Prompt',
            minLines: 4,
            maxLines: 8,
            onCommandEnter: () => submits += 1,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Build it');
    await tester.sendKeyDownEvent(.controlLeft);
    expect(await tester.sendKeyDownEvent(.enter), isTrue);
    expect(await tester.sendKeyRepeatEvent(.enter), isFalse);
    await tester.sendKeyUpEvent(.enter);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pump();
    expect(submits, 1);
  });

  testWidgets('toggling onCommandEnter keeps the editing state', (
    tester,
  ) async {
    var submits = 0;
    final controller = TextEditingController();
    final focusNode = FocusNode();
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);

    Future<void> pumpField({required VoidCallback? onCommandEnter}) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AleraTextField(
              controller: controller,
              focusNode: focusNode,
              labelText: 'Initial Prompt',
              minLines: 4,
              maxLines: 8,
              onCommandEnter: onCommandEnter,
            ),
          ),
        ),
      );
    }

    await pumpField(onCommandEnter: null);
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Build it');
    controller
      ..selection = const TextSelection.collapsed(offset: 5)
      ..value = controller.value.copyWith(
        composing: const TextRange(start: 3, end: 5),
      );
    await tester.pump();
    final editingState = tester.state<EditableTextState>(
      find.byType(EditableText),
    );

    await pumpField(onCommandEnter: () => submits += 1);
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editingState),
    );
    expect(focusNode.hasFocus, isTrue);
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
    expect(controller.value.composing, const TextRange(start: 3, end: 5));

    await tester.sendKeyDownEvent(.controlLeft);
    expect(await tester.sendKeyEvent(.enter), isTrue);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pump();
    expect(submits, 1);

    await pumpField(onCommandEnter: null);
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(editingState),
    );
    expect(focusNode.hasFocus, isTrue);
    expect(controller.selection, const TextSelection.collapsed(offset: 5));
    expect(controller.value.composing, const TextRange(start: 3, end: 5));

    await tester.sendKeyDownEvent(.controlLeft);
    expect(await tester.sendKeyEvent(.enter), isFalse);
    await tester.sendKeyUpEvent(.controlLeft);
    await tester.pump();
    expect(submits, 1);
  });
}
