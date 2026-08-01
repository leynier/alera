part of 'settings_dialog_test.dart';

void _registerSettingsDialogAiTextTests() {
  testWidgets('keeps AI Text reasoning selections isolated per operation', (
    tester,
  ) async {
    final container = await _pumpSettingsDialog(tester);
    await tester.tap(find.text('AI Text').first);
    await tester.pump();

    final commitReasoning = find.byKey(
      const ValueKey<String>('ai-text-commitMessage-reasoning-low'),
    );
    await tester.ensureVisible(commitReasoning);
    await tester.tap(commitReasoning);
    await tester.pumpAndSettle();
    await tester.tap(find.text('High').last);
    await tester.pump(const Duration(milliseconds: 50));

    final settings = container
        .read(settingsControllerProvider)
        .aiTextGeneration;
    expect(
      settings.selectedThinkingByOperation[AiTextGenerationOperation
          .commitMessage]?['gpt-5.5'],
      'high',
    );
    expect(
      settings.thinkingForOperation(
        AiTextGenerationOperation.commitMessage,
        'gpt-5.5',
      ),
      'high',
    );
    expect(
      settings.thinkingForOperation(
        AiTextGenerationOperation.pullRequestDetails,
        'gpt-5.5',
      ),
      isNull,
    );
    expect(settings.thinkingForModel('gpt-5.5'), isNull);
    expect(
      find.byKey(
        const ValueKey<String>('ai-text-pullRequestDetails-reasoning-low'),
      ),
      findsOneWidget,
    );
  });
}
