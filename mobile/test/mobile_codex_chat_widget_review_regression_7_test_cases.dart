part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexReviewRegression7Tests() {
  testWidgets('mobile removes a mention token with its attachment chip', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      workspaceFiles: const <String>['docs/notes.md'],
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-mention-delete');

    final composer = find.byType(TextField).last;
    await tester.enterText(composer, '@notes');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'docs/notes.md'));
    await tester.pump();

    expect(
      tester.widget<TextField>(composer).controller!.text,
      'docs/notes.md ',
    );
    final chip = tester.widget<InputChip>(
      find.widgetWithText(InputChip, 'notes.md'),
    );
    chip.onDeleted!();
    await tester.pump();

    expect(tester.widget<TextField>(composer).controller!.text, isEmpty);
    expect(find.widgetWithText(InputChip, 'notes.md'), findsNothing);
    final sendButton = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Send',
    );
    expect(tester.widget<IconButton>(sendButton).onPressed, isNull);
  });
}
