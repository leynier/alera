part of 'ai_assist_service_test.dart';

void _registerChatGptAiAssistTests() {
  test('ChatGPT preserves provider settings and is tool free', () {
    const settings = AiAssistSettings(agent: AiAssistAgent.chatgpt);
    expect(
      AiAssistSettings.fromJson(settings.toMap()).agent,
      AiAssistAgent.chatgpt,
    );
    expect(supportsDiffOnlyAiAssistAgent(AiAssistAgent.chatgpt), isTrue);
    expect(
      aiAssistAgentSpecs[AiAssistAgent.chatgpt]!.supportsRepositoryRead,
      isFalse,
    );
    expect(defaultModelIdForAgent(AiAssistAgent.chatgpt, settings), isEmpty);
  });

  test(
    'ChatGPT routes to its runtime without starting a CLI or another provider',
    () async {
      final process = _FakeProcessRunner(stdout: 'should-not-run');
      final chatgpt = _FakeOpenCodeGoCompleter(text: 'feat: connected');
      final other = _FakeOpenCodeGoCompleter();
      final runner = CliAiAssistAgentRunner(
        processRunner: process,
        hostCompleter: other,
        chatGptCompleter: chatgpt,
      );
      final result = await runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(agent: AiAssistAgent.chatgpt),
          prompt: 'Summarize this diff',
          runId: 'chatgpt-run',
          workingDirectory: '/repo',
          model: 'account-model',
        ),
      );
      expect(result.text, 'feat: connected');
      expect(chatgpt.lastModel, 'account-model');
      expect(chatgpt.lastPrompt, 'Summarize this diff');
      expect(other.completeCount, 0);
      expect(process.started, isFalse);
    },
  );

  test('ChatGPT discovery uses the runtime account catalog in order', () async {
    final process = _FakeProcessRunner(stdout: 'should-not-run');
    final chatgpt = _FakeOpenCodeGoCompleter(
      models: const [
        AiAssistModel(id: 'b', label: 'Account B'),
        AiAssistModel(id: 'a', label: 'Account A'),
      ],
    );
    final result = await CliAiAssistModelDiscoveryService(
      processRunner: process,
      chatGptCompleter: chatgpt,
    ).discover(AiAssistAgent.chatgpt);
    expect(result.success, isTrue);
    expect(result.models.map((model) => model.id), ['b', 'a']);
    expect(result.defaultModelId, 'b');
    expect(process.started, isFalse);
  });

  test('ChatGPT errors never fall back to a CLI', () async {
    final process = _FakeProcessRunner(stdout: 'should-not-run');
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      chatGptCompleter: _FakeOpenCodeGoCompleter(
        error: const AiAssistException('ChatGPT usage limit reached.'),
      ),
    );
    await expectLater(
      runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(agent: AiAssistAgent.chatgpt),
          prompt: 'text',
          runId: 'limited',
          workingDirectory: '/repo',
        ),
      ),
      throwsA(isA<AiAssistException>()),
    );
    expect(process.started, isFalse);
  });
}
