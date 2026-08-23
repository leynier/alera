part of 'mobile_codex_chat_widget_test.dart';

void _registerMobileCodexModelMenuTests() {
  testWidgets('mobile model configuration stays open after a selection', (
    tester,
  ) async {
    final client = FakeMobileCodexClient();
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-model-menu');

    await tester.tap(find.textContaining('Current Codex'));
    await tester.pumpAndSettle();
    expect(find.text('Reasoning Effort'), findsOneWidget);

    await tester.tap(find.text('Xhigh'));
    await tester.pumpAndSettle();

    expect(find.text('Model'), findsOneWidget);
    expect(find.text('Reasoning Effort'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
    expect(client.configuration?['reasoningEffort'], 'xhigh');
  });

  testWidgets('mobile model selection refreshes supported menu options', (
    tester,
  ) async {
    final client = FakeMobileCodexClient(
      configuration: <String, Object?>{
        'selectedModel': 'gpt-fast',
        'reasoningEffort': 'xhigh',
        'speedMode': 'fast',
      },
      responses: const <String, Map<String, Object?>>{
        'codex.model.list': <String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'id': 'gpt-fast',
              'displayName': 'GPT-Fast Codex',
              'isDefault': true,
              'supportedReasoningEfforts': <String>['low', 'xhigh'],
              'additionalSpeedTiers': <String>['fast'],
            },
            <String, Object?>{
              'id': 'gpt-compact',
              'displayName': 'GPT-Compact Codex',
              'supportedReasoningEfforts': <String>['high'],
              'defaultReasoningEffort': 'high',
            },
          ],
        },
      },
    );
    addTearDown(client.dispose);
    await _pumpScreen(tester, client: client, hostId: 'host-model-options');

    await tester.tap(find.textContaining('Fast Codex'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Speed'), findsOneWidget);

    await tester.tap(find.text('Standard'));
    await tester.pump();
    expect(find.text('Speed'), findsOneWidget);
    expect(client.configuration?['speedMode'], 'normal');

    await tester.drag(find.byType(ListView).last, const Offset(0, 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compact Codex'));
    await tester.pumpAndSettle();

    expect(find.text('Model'), findsOneWidget);
    expect(find.text('High'), findsOneWidget);
    expect(find.text('Speed'), findsNothing);
    expect(client.configuration?['selectedModel'], 'gpt-compact');
    expect(client.configuration?['reasoningEffort'], 'high');
    expect(client.configuration?['speedMode'], 'normal');
  });
}
