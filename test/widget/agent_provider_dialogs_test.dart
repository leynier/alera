import 'package:alera/src/app/theme/alera_dark_theme.dart';
import 'package:alera/src/app/theme/alera_tokens.dart';
import 'package:alera/src/design_system/buttons/alera_icon_button.dart';
import 'package:alera/src/design_system/layout/alera_dialog_header.dart';
import 'package:alera/src/features/agent_provider_settings/domain/agent_provider_instance_draft.dart';
import 'package:alera/src/features/agent_provider_settings/presentation/agent_provider_dialogs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final Finder _surface = find
    .descendant(of: find.byType(Dialog), matching: find.byType(Material))
    .first;
final Finder _title = find.descendant(
  of: find.byType(AleraDialogHeader),
  matching: find.text('Add Provider'),
);
final Finder _close = find.descendant(
  of: find.byType(AleraDialogHeader),
  matching: find.byType(AleraIconButton),
);
final Finder _submit = find.widgetWithText(FilledButton, 'Add Provider');

Future<List<AgentProviderInstanceDraft?>> _open(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final results = <AgentProviderInstanceDraft?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAleraDarkTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => results.add(
              await showAddAgentProviderDialog(
                context,
                takenIds: const <String>{},
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('the header shares the body inset instead of the dialog edge', (
    tester,
  ) async {
    final results = await _open(tester, size: const Size(1200, 900));
    final surface = tester.getRect(_surface);
    final title = tester.getRect(_title);
    final close = tester.getRect(_close);
    final body = tester.getRect(find.textContaining('Run a second'));

    expect(title.left - surface.left, moreOrLessEquals(AleraTokens.space20));
    expect(title.top - surface.top, greaterThanOrEqualTo(AleraTokens.space20));
    expect(surface.right - close.right, moreOrLessEquals(AleraTokens.space20));
    expect(close.top - surface.top, moreOrLessEquals(AleraTokens.space20));
    expect(body.left, moreOrLessEquals(title.left));
    expect(body.top, greaterThan(title.bottom));

    await tester.tap(_submit);
    await tester.pumpAndSettle();
    expect(results.single?.providerInstanceId, 'codex-2');
  });

  testWidgets('a short window with large text keeps the inset and actions', (
    tester,
  ) async {
    await _open(tester, size: const Size(360, 480), textScale: 2);
    expect(tester.takeException(), isNull);

    final surface = tester.getRect(_surface);
    expect(
      tester.getRect(_title).left - surface.left,
      moreOrLessEquals(AleraTokens.space20),
    );
    expect(
      surface.right - tester.getRect(_close).right,
      moreOrLessEquals(AleraTokens.space20),
    );
    final submit = tester.getRect(_submit);
    expect(surface.contains(submit.topLeft), isTrue);
    expect(surface.contains(submit.bottomRight), isTrue);

    await tester.ensureVisible(find.widgetWithText(TextField, 'Label'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Label').hitTestable(), findsOne);
    expect(tester.takeException(), isNull);
  });
}
