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
      expect(chatgpt.lastThinkingLevel, isNull);
      expect(chatgpt.lastServiceTier, aiAssistChatGptDefaultServiceTier);
      expect(other.completeCount, 0);
      expect(process.started, isFalse);
    },
  );

  test('ChatGPT forwards the selected reasoning and service tier', () async {
    final process = _FakeProcessRunner(stdout: 'should-not-run');
    final chatgpt = _FakeOpenCodeGoCompleter(text: 'feat: connected');
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      chatGptCompleter: chatgpt,
    );

    await runner.run(
      const AiAssistAgentRunRequest(
        settings: AiAssistSettings(
          agent: AiAssistAgent.chatgpt,
          selectedThinkingByModel: <String, String>{'account-model': 'high'},
          chatGptServiceTier: aiAssistChatGptFastServiceTier,
        ),
        prompt: 'Summarize this diff',
        runId: 'chatgpt-options',
        workingDirectory: '/repo',
        agent: AiAssistAgent.chatgpt,
        model: 'account-model',
      ),
    );

    expect(chatgpt.lastThinkingLevel, 'high');
    expect(chatgpt.lastServiceTier, aiAssistChatGptFastServiceTier);
  });

  test(
    'an explicit request reasoning value wins over the saved model value',
    () async {
      final chatgpt = _FakeOpenCodeGoCompleter(text: 'feat: connected');
      final runner = CliAiAssistAgentRunner(
        processRunner: _FakeProcessRunner(stdout: 'should-not-run'),
        chatGptCompleter: chatgpt,
      );

      await runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(
            agent: AiAssistAgent.chatgpt,
            selectedThinkingByModel: <String, String>{'account-model': 'high'},
          ),
          prompt: 'Summarize this diff',
          runId: 'chatgpt-explicit-options',
          workingDirectory: '/repo',
          agent: AiAssistAgent.chatgpt,
          model: 'account-model',
          reasoning: 'low',
        ),
      );

      expect(chatgpt.lastThinkingLevel, 'low');
      expect(chatgpt.lastServiceTier, aiAssistChatGptDefaultServiceTier);
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

  test(
    'ChatGPT discovery preserves dynamic models and sanitized options',
    () async {
      final client = _ChatGptRuntimeHostClient(
        capabilities: <String>{aleraRuntimeHostAiAssistChatGptCapability},
        responses: <String, Object?>{
          'aiAssist.chatgpt.models': <String, Object?>{
            'models': <Object?>[
              <String, Object?>{
                'id': ' gpt-6.1-sol ',
                'label': ' GPT-6.1 Sol ',
                'thinkingLevels': <Object?>[
                  <String, Object?>{'id': ' low ', 'label': ' Low '},
                  <String, Object?>{'id': 'high'},
                  <String, Object?>{'id': 'low', 'label': 'duplicate'},
                  <String, Object?>{'label': 'missing id'},
                  'invalid',
                ],
                'defaultThinkingLevel': ' high ',
              },
              <String, Object?>{'id': 'gpt-6-luna', 'label': 'GPT-6 Luna'},
            ],
          },
        },
      );

      final models = await RuntimeHostAiAssistCompleter(
        client: client,
        agent: AiAssistAgent.chatgpt,
      ).discoverModels();

      expect(models.map((model) => model.id), <String>[
        'gpt-6.1-sol',
        'gpt-6-luna',
      ]);
      expect(models.first.thinkingLevels.map((level) => level.id), <String>[
        'low',
        'high',
      ]);
      expect(models.first.thinkingLevels.first.label, 'Low');
      expect(models.first.defaultThinkingLevel, 'high');
    },
  );

  test(
    'ChatGPT options are rejected by an older host instead of being lost',
    () async {
      final client = _ChatGptRuntimeHostClient(
        capabilities: <String>{aleraRuntimeHostAiAssistChatGptCapability},
        responses: <String, Object?>{
          'aiAssist.complete': <String, Object?>{
            'text': 'should-not-run',
            'agentLabel': 'ChatGPT',
          },
        },
      );

      await expectLater(
        RuntimeHostAiAssistCompleter(
          client: client,
          agent: AiAssistAgent.chatgpt,
        ).complete(
          prompt: 'text',
          model: 'gpt-6.1-sol',
          sessionId: 'session',
          operationId: 'operation',
          timeoutSeconds: 30,
          thinkingLevel: 'high',
        ),
        throwsA(
          isA<AiAssistException>().having(
            (error) => error.message,
            'message',
            chatGptOptionsHostTooOldMessage,
          ),
        ),
      );
      expect(client.requestedTypes, isNot(contains('aiAssist.complete')));
    },
  );

  test(
    'ChatGPT fast mode is rejected by an older host instead of being lost',
    () async {
      final client = _ChatGptRuntimeHostClient(
        capabilities: <String>{aleraRuntimeHostAiAssistChatGptCapability},
        responses: <String, Object?>{
          'aiAssist.complete': <String, Object?>{
            'text': 'should-not-run',
            'agentLabel': 'ChatGPT',
          },
        },
      );

      await expectLater(
        RuntimeHostAiAssistCompleter(
          client: client,
          agent: AiAssistAgent.chatgpt,
        ).complete(
          prompt: 'text',
          model: 'gpt-6.1-sol',
          sessionId: 'session',
          operationId: 'operation-fast',
          timeoutSeconds: 30,
          serviceTier: aiAssistChatGptFastServiceTier,
        ),
        throwsA(
          isA<AiAssistException>().having(
            (error) => error.message,
            'message',
            chatGptOptionsHostTooOldMessage,
          ),
        ),
      );
      expect(client.requestedTypes, isNot(contains('aiAssist.complete')));
    },
  );

  test(
    'ChatGPT default options stay compatible with the base host capability',
    () async {
      final client = _ChatGptRuntimeHostClient(
        capabilities: <String>{aleraRuntimeHostAiAssistChatGptCapability},
        responses: <String, Object?>{
          'aiAssist.complete': <String, Object?>{
            'text': 'ok',
            'agentLabel': 'ChatGPT',
          },
        },
      );

      await RuntimeHostAiAssistCompleter(
        client: client,
        agent: AiAssistAgent.chatgpt,
      ).complete(
        prompt: 'text',
        model: 'gpt-6.1-sol',
        sessionId: 'session',
        operationId: 'operation',
        timeoutSeconds: 30,
        serviceTier: aiAssistChatGptDefaultServiceTier,
      );

      expect(client.lastPayload, isNot(contains('thinkingLevel')));
      expect(
        client.lastPayload?['serviceTier'],
        aiAssistChatGptDefaultServiceTier,
      );
      expect(client.lastPayload, isNot(contains('thinkingContext')));
    },
  );

  test(
    'ChatGPT forwards advanced options when the host advertises support',
    () async {
      final client = _ChatGptRuntimeHostClient(
        capabilities: <String>{
          aleraRuntimeHostAiAssistChatGptCapability,
          aleraRuntimeHostAiAssistChatGptOptionsCapability,
        },
        responses: <String, Object?>{
          'aiAssist.complete': <String, Object?>{
            'text': 'ok',
            'agentLabel': 'ChatGPT',
          },
        },
      );

      await RuntimeHostAiAssistCompleter(
        client: client,
        agent: AiAssistAgent.chatgpt,
      ).complete(
        prompt: 'text',
        model: 'gpt-6.1-sol',
        sessionId: 'session',
        operationId: 'operation-advanced',
        timeoutSeconds: 30,
        thinkingLevel: 'high',
        serviceTier: aiAssistChatGptFastServiceTier,
        thinkingContext: const AiAssistThinkingContext(
          operation: AiAssistOperation.commitMessage,
          selectedThinkingByModel: <String, String>{'gpt-6.1-sol': 'high'},
          selectedThinkingByOperation: <String, String>{'gpt-6.1-sol': 'xhigh'},
        ),
      );

      expect(client.lastPayload?['thinkingLevel'], 'high');
      expect(
        client.lastPayload?['serviceTier'],
        aiAssistChatGptFastServiceTier,
      );
      expect(client.lastPayload?['thinkingContext'], <String, Object?>{
        'operation': AiAssistOperation.commitMessage.key,
        'selectedThinkingByModel': <String, String>{'gpt-6.1-sol': 'high'},
        'selectedThinkingByOperation': <String, String>{'gpt-6.1-sol': 'xhigh'},
      });
    },
  );
}

final class _ChatGptRuntimeHostClient
    implements RuntimeHostClient, RuntimeHostCapabilityClient {
  _ChatGptRuntimeHostClient({
    required this.capabilities,
    required this.responses,
  });

  final Set<String> capabilities;
  final Map<String, Object?> responses;
  final List<String> requestedTypes = <String>[];
  Map<String, Object?>? lastPayload;

  @override
  Stream<RuntimeHostEvent> get runtimeEvents => const Stream.empty();

  @override
  Future<bool> supportsRuntimeCapability(String capability) async =>
      capabilities.contains(capability);

  @override
  Future<Object?> runtimeRequest(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration? timeout,
  ]) async {
    requestedTypes.add(type);
    lastPayload = payload;
    return responses[type];
  }
}
