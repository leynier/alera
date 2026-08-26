part of 'settings_dialog_test.dart';

void _registerSettingsDialogAiAssistTests() {
  testWidgets('keeps AI Assist reasoning selections isolated per operation', (
    tester,
  ) async {
    final container = await _pumpSettingsDialog(
      tester,
      initialSectionId: 'aiAssist',
    );
    // Jump via the subsection chip so the commit-message reasoning control is
    // in the content viewport before the dropdown opens.
    await tester.tap(find.text('Commit Messages').first);
    await tester.pumpAndSettle();

    final commitReasoning = find.byKey(
      const ValueKey<String>('ai-assist-commitMessage-reasoning-low'),
    );
    await tester.ensureVisible(commitReasoning);
    await tester.pump();
    await tester.tap(commitReasoning);
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pump(const Duration(milliseconds: 50));

    final settings = container.read(settingsControllerProvider).aiAssist;
    expect(
      settings.selectedThinkingByOperation[AiAssistOperation
          .commitMessage]?['gpt-5.5'],
      'high',
    );
    expect(
      settings.thinkingForOperation(AiAssistOperation.commitMessage, 'gpt-5.5'),
      'high',
    );
    expect(
      settings.thinkingForOperation(
        AiAssistOperation.pullRequestDetails,
        'gpt-5.5',
      ),
      isNull,
    );
    expect(settings.thinkingForModel('gpt-5.5'), isNull);
    expect(
      find.byKey(
        const ValueKey<String>('ai-assist-pullRequestDetails-reasoning-low'),
      ),
      findsOneWidget,
    );
  });
}
