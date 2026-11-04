import 'package:alera_mobile/src/features/agent_provider_settings/presentation/agent_provider_secret_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/phone_modal_harness.dart';

Future<List<String?>> _openSecret(WidgetTester tester, double scale) async {
  final answers = <String?>[];
  await openFromPhone(
    tester,
    textScale: scale,
    open: (context) async => answers.add(
      await showAgentProviderSecretDialog(
        context,
        name: 'OPENAI_API_KEY',
        replacing: true,
      ),
    ),
  );
  return answers;
}

void main() {
  setUpAll(loadShippedInter);

  for (final scale in <double>[1, 2]) {
    testWidgets('a short phone with the keyboard keeps Save usable at $scale', (
      tester,
    ) async {
      usePhone(tester, size: const Size(320, 568), keyboard: 260);
      final answers = await _openSecret(tester, scale);

      expect(tester.takeException(), isNull);
      final save = find.widgetWithText(FilledButton, 'Save');
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      expect(
        tester.getRect(save).bottom,
        lessThanOrEqualTo(visibleBottom(tester)),
      );
      expect(
        tester.getRect(cancel).bottom,
        lessThanOrEqualTo(visibleBottom(tester)),
      );
      final field = find.byType(TextField);
      final input = tester.widget<TextField>(field);
      expect(input.obscureText, isTrue);
      expect(input.enableSuggestions, isFalse);
      expect(input.autocorrect, isFalse);
      final editable = tester.widget<EditableText>(
        find.descendant(of: field, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(editable.obscureText, isTrue);
      expect(tester.widget<FilledButton>(save).onPressed, isNull);

      await tester.enterText(field, 'not-a-real-key');
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      expect(tester.getRect(field).top, lessThan(visibleBottom(tester)));
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(answers, <String?>['not-a-real-key']);
    });
  }

  testWidgets('Cancel returns nothing', (tester) async {
    usePhone(tester, size: const Size(320, 568), keyboard: 260);
    final answers = await _openSecret(tester, 2);
    await tester.enterText(find.byType(TextField), 'typed');
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(answers, <String?>[null]);
  });
}
