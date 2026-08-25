part of 'ai_assist_service_test.dart';

void _registerFxAiAssistTests() {
  test('parses fx model JSON using exact model ids', () {
    final models = parseFxModels('''
{"kind":"models","count":2,"models":[{"id":"xai/grok-4.1-fast","source":"pi"},{"id":"openai/gpt-5.4","source":"pi"}]}
''');

    expect(models.map((model) => model.id), <String>[
      'xai/grok-4.1-fast',
      'openai/gpt-5.4',
    ]);
    expect(models.map((model) => model.label), <String>[
      'Xai Grok 4.1 Fast',
      'Openai GPT 5.4',
    ]);
  });

  test(
    'runs fx ask through stdin with conservative process settings',
    () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/fx',
        )
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/fx.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
            ),
          ],
        );
      final runner = _FakeProcessRunner(stdout: 'feat: add fx support\n');
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
      );

      final result = await service.generate(
        const AiAssistRequest(
          operation: AiAssistOperation.commitMessage,
          workspacePath: '/repo',
          settings: AiAssistSettings(agent: AiAssistAgent.fx),
        ),
      );

      expect(result.text, 'feat: add fx support');
      expect(runner.executable, 'fx');
      expect(runner.arguments, <String>['ask', '--no-save']);
      expect(runner.stdinText, contains('feature/fx'));
      expect(runner.stdinClosed, isTrue);
      expect(runner.environment, containsPair('FX_PERMISSION_MODE', 'ask'));
      expect(runner.environment, containsPair('FX_AUTO_UPGRADE', '0'));
      expect(runner.environment, containsPair('FX_HERDR', '0'));
      expect(runner.environment, isNot(contains('FX_MODEL')));
    },
  );

  test('passes an explicit fx model through FX_MODEL', () async {
    final git = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'feature/fx',
      )
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/fx.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );
    final runner = _FakeProcessRunner(stdout: 'feat: add fx support\n');
    final service = CliAiAssistService(gitBackend: git, processRunner: runner);

    await service.generate(
      const AiAssistRequest(
        operation: AiAssistOperation.commitMessage,
        workspacePath: '/repo',
        settings: AiAssistSettings(
          agent: AiAssistAgent.fx,
          selectedModelByAgent: <AiAssistAgent, String>{
            AiAssistAgent.fx: 'xai/grok-4.1-fast',
          },
        ),
      ),
    );

    expect(runner.environment, containsPair('FX_MODEL', 'xai/grok-4.1-fast'));
  });

  test('discovers fx models through JSON output', () async {
    final runner = _FakeProcessRunner(
      stdout:
          '{"kind":"models","count":1,"models":[{"id":"xai/grok-4.1-fast","source":"pi"}]}',
    );
    final service = CliAiAssistModelDiscoveryService(processRunner: runner);

    final result = await service.discover(AiAssistAgent.fx);

    expect(result.success, isTrue);
    expect(result.defaultModelId, isNull);
    expect(result.models.single.id, 'xai/grok-4.1-fast');
    expect(runner.executable, 'fx');
    expect(runner.arguments, <String>['models', '--json']);
  });
}
