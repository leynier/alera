import 'package:alera_agent_chat/alera_agent_chat.dart';
import 'package:alera_mobile/src/design_system/forms/alera_rename_dialog.dart';
import 'package:alera_mobile/src/design_system/layout/alera_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/phone_modal_harness.dart';

const Size _shortPhone = Size(320, 568);

Future<List<bool?>> _openConfirm(WidgetTester tester, double scale) async {
  final answers = <bool?>[];
  const kind = AgentChatRewindKind.conversation;
  await openFromPhone(
    tester,
    textScale: scale,
    open: (context) async => answers.add(
      await showDialog<bool>(
        context: context,
        builder: (_) => AleraConfirmDialog(
          title: agentChatRewindConfirmTitle(kind),
          message: agentChatRewindConfirmMessage(kind),
          confirmLabel: agentChatRewindConfirmLabel(kind),
          destructive: true,
        ),
      ),
    ),
  );
  return answers;
}

Future<List<String?>> _openAddModel(WidgetTester tester, double scale) async {
  final answers = <String?>[];
  await openFromPhone(
    tester,
    textScale: scale,
    open: (context) async => answers.add(
      await showDialog<String>(
        context: context,
        builder: (_) => const AleraRenameDialog(
          title: 'Add Custom Model',
          labelText: 'Model ID',
          helperText: 'Exactly as the agent names it, for example gpt-5.',
          confirmLabel: 'Add',
        ),
      ),
    ),
  );
  return answers;
}

void main() {
  setUpAll(loadShippedInter);

  group('AleraConfirmDialog', () {
    testWidgets('long copy at 200% scrolls and keeps the decision', (
      tester,
    ) async {
      usePhone(tester, size: _shortPhone);
      final answers = await _openConfirm(tester, 2);

      expect(tester.takeException(), isNull);
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      final rewind = find.widgetWithText(FilledButton, 'Rewind');
      expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(568));
      expect(tester.getRect(rewind).bottom, lessThanOrEqualTo(568));
      final copy = find.textContaining('Files stay as they are.');
      final body = find.descendant(
        of: find.byType(AleraConfirmDialog),
        matching: find.byType(SingleChildScrollView),
      );
      await tester.drag(body, const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(copy).bottom,
        lessThanOrEqualTo(tester.getRect(rewind).top),
      );

      await tester.tap(rewind);
      await tester.pumpAndSettle();
      expect(answers, <bool?>[true]);
    });

    testWidgets('Cancel still answers false', (tester) async {
      usePhone(tester, size: _shortPhone);
      final answers = await _openConfirm(tester, 2);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(answers, <bool?>[false]);
    });
  });

  group('AleraRenameDialog', () {
    for (final scale in <double>[1, 2]) {
      testWidgets('the keyboard leaves the field and Add usable at $scale', (
        tester,
      ) async {
        usePhone(tester, size: _shortPhone, keyboard: 260);
        final answers = await _openAddModel(tester, scale);

        expect(tester.takeException(), isNull);
        final add = find.widgetWithText(FilledButton, 'Add');
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        final field = find.byType(TextField);
        expect(
          tester.getRect(add).bottom,
          lessThanOrEqualTo(visibleBottom(tester)),
        );
        expect(
          tester.getRect(cancel).bottom,
          lessThanOrEqualTo(visibleBottom(tester)),
        );
        expect(
          tester
              .widget<EditableText>(
                find.descendant(of: field, matching: find.byType(EditableText)),
              )
              .focusNode
              .hasFocus,
          isTrue,
        );

        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(answers, isEmpty, reason: 'an empty ID keeps the dialog open');

        await tester.enterText(field, '  gpt-6  ');
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        expect(tester.getRect(field).top, lessThan(visibleBottom(tester)));
        await tester.tap(add);
        await tester.pumpAndSettle();
        expect(answers, <String?>['gpt-6']);
      });
    }
  });
}
