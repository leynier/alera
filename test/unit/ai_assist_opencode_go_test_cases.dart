part of 'ai_assist_service_test.dart';

class _FakeOpenCodeGoCompleter implements AiAssistHostCompleter {
  _FakeOpenCodeGoCompleter({
    this.text = 'feat: add go assist',
    this.error,
    this.models = const <AiAssistModel>[
      AiAssistModel(id: 'glm-5.3-flash', label: 'GLM-5.3-Flash'),
      AiAssistModel(id: 'kimi-k3', label: 'Kimi K3'),
    ],
    this.discoverError,
  });

  final String text;
  final Object? error;
  final List<AiAssistModel> models;
  final Object? discoverError;
  int completeCount = 0;
  int cancelCount = 0;
  String? lastPrompt;
  String? lastModel;
  String? lastSessionId;
  String? lastOperationId;

  @override
  Future<AiAssistAgentRunResult> complete({
    required String prompt,
    required String model,
    required String sessionId,
    required String operationId,
    required int timeoutSeconds,
  }) async {
    completeCount += 1;
    lastPrompt = prompt;
    lastModel = model;
    lastSessionId = sessionId;
    lastOperationId = operationId;
    final thrown = error;
    if (thrown != null) {
      throw thrown;
    }
    return AiAssistAgentRunResult(text: text, agentLabel: 'OpenCode Go');
  }

  @override
  Future<void> cancel(String operationId) async {
    cancelCount += 1;
  }

  @override
  Future<List<AiAssistModel>> discoverOpenCodeGoModels() async {
    final thrown = discoverError;
    if (thrown != null) {
      throw thrown;
    }
    return models;
  }
}

void _registerOpenCodeGoAiAssistTests() {
  test(
    'routes OpenCode Go through the host completer without a CLI spawn',
    () async {
      final process = _FakeProcessRunner(stdout: 'should-not-run');
      final host = _FakeOpenCodeGoCompleter();
      final runner = CliAiAssistAgentRunner(
        processRunner: process,
        hostCompleter: host,
      );

      final result = await runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(agent: .opencodeGo),
          prompt: 'Write a commit message.',
          runId: 'go-run',
          workingDirectory: '/repo',
          agent: .opencodeGo,
          model: 'glm-5.3-flash',
        ),
      );

      expect(process.started, isFalse);
      expect(host.completeCount, 1);
      expect(host.lastPrompt, 'Write a commit message.');
      expect(host.lastModel, 'glm-5.3-flash');
      expect(host.lastSessionId, 'go-run');
      expect(host.lastOperationId, 'go-run');
      expect(result.text, 'feat: add go assist');
      expect(result.agentLabel, 'OpenCode Go');
    },
  );

  test('surfaces a missing OpenCode Go API key from the host', () async {
    final process = _FakeProcessRunner(stdout: 'should-not-run');
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      hostCompleter: _FakeOpenCodeGoCompleter(
        error: const AiAssistException('OpenCode Go API key was not found'),
      ),
    );

    await expectLater(
      runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(agent: .opencodeGo),
          prompt: 'Write a commit message.',
          runId: 'go-missing-key',
          workingDirectory: '/repo',
          agent: .opencodeGo,
        ),
      ),
      throwsA(
        isA<AiAssistException>().having(
          (error) => error.message,
          'message',
          'OpenCode Go API key was not found',
        ),
      ),
    );
    expect(process.started, isFalse);
  });

  test(
    'falls back to the static OpenCode Go catalog when discovery fails',
    () async {
      final process = _FakeProcessRunner(stdout: 'should-not-run');
      final discovery = CliAiAssistModelDiscoveryService(
        processRunner: process,
        hostCompleter: _FakeOpenCodeGoCompleter(
          discoverError: const AiAssistException(
            'The running terminal host does not support OpenCode Go AI Assist.',
          ),
        ),
      );

      final result = await discovery.discover(AiAssistAgent.opencodeGo);

      expect(process.started, isFalse);
      expect(result.success, isFalse);
      expect(result.models, openCodeGoStaticModels);
      expect(result.defaultModelId, openCodeGoDefaultModelId);
      expect(
        result.error,
        'The running terminal host does not support OpenCode Go AI Assist.',
      );
    },
  );

  test('allows OpenCode Go for reading diffs without spawning a CLI', () async {
    final process = _FakeProcessRunner(stdout: 'should-not-run');
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      hostCompleter: _FakeOpenCodeGoCompleter(
        text: '{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep."}',
      ),
    );

    final result = await runner.run(
      const AiAssistAgentRunRequest(
        settings: AiAssistSettings(agent: .opencodeGo),
        prompt: 'Plan this diff.',
        runId: 'go-diff',
        workingDirectory: '/repo',
        agent: .opencodeGo,
        accessPolicy: .diffOnly,
        outputContract: .readingDiffPlanV1,
      ),
    );

    expect(process.started, isFalse);
    expect(supportsDiffOnlyAiAssistAgent(AiAssistAgent.opencodeGo), isTrue);
    expect(result.text, contains('"version":1'));
  });

  test(
    'discovers live OpenCode Go models through the host completer',
    () async {
      final process = _FakeProcessRunner(stdout: 'should-not-run');
      final discovery = CliAiAssistModelDiscoveryService(
        processRunner: process,
        hostCompleter: _FakeOpenCodeGoCompleter(
          models: const <AiAssistModel>[
            AiAssistModel(id: 'kimi-k3', label: 'Kimi K3'),
          ],
        ),
      );

      final result = await discovery.discover(AiAssistAgent.opencodeGo);

      expect(process.started, isFalse);
      expect(result.success, isTrue);
      expect(result.models.single.id, 'kimi-k3');
      expect(result.defaultModelId, 'kimi-k3');
    },
  );
}
