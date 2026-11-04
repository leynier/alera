import 'package:alera/src/design_system/forms/alera_composer.dart';
import 'package:alera/src/design_system/forms/alera_text_actions_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Uncommitted IME text, as a Japanese input method leaves it before the
/// candidate is confirmed.
const TextEditingValue _composing = TextEditingValue(
  text: 'にほん',
  selection: TextSelection.collapsed(offset: 3),
  composing: TextRange(start: 0, end: 3),
);

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  late int sends;
  late int closes;

  Future<void> pumpComposer(WidgetTester tester) async {
    controller = TextEditingController();
    focusNode = FocusNode();
    sends = 0;
    closes = 0;
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AleraComposer(
            controller: controller,
            focusNode: focusNode,
            onSend: () => sends += 1,
            onClose: () => closes += 1,
            textActions: const <AleraTextActionMenuItem>[],
            onTextActionSelected: (_) {},
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
    controller.value = _composing;
    await tester.pump();
  }

  testWidgets(
    'Enter, its modifiers and Escape reach the input method while composing',
    (tester) async {
      await pumpComposer(tester);

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter),
        isFalse,
      );
      for (final modifier in <LogicalKeyboardKey>[
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaLeft,
      ]) {
        await tester.sendKeyDownEvent(modifier);
        expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isFalse);
        await tester.sendKeyUpEvent(modifier);
      }
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isFalse);
      await tester.pump();

      expect(sends, 0);
      expect(closes, 0);
      expect(controller.value, _composing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'Enter sends and Escape closes again once the composition is committed',
    (tester) async {
      await pumpComposer(tester);
      controller.value = const TextEditingValue(
        text: '日本',
        selection: TextSelection.collapsed(offset: 2),
      );
      await tester.pump();

      expect(await tester.sendKeyEvent(LogicalKeyboardKey.enter), isTrue);
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.escape), isTrue);
      await tester.pump();

      expect(sends, 1);
      expect(closes, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
