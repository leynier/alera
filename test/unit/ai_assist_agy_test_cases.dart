part of 'ai_assist_service_test.dart';

void _registerAgyAiAssistTests() {
  test('parses agy model output as exact ids with readable labels', () {
    final models = parseAgyModels('''
Available models:
- gemini-3.6-flash-high
gemini-3.1-pro-low
claude-opus-4-6-thinking
Gemini 3.5 Flash (Medium)
''');

    expect(models.map((model) => model.id), <String>[
      'gemini-3.6-flash-high',
      'gemini-3.1-pro-low',
      'claude-opus-4-6-thinking',
      'Gemini 3.5 Flash (Medium)',
    ]);
    expect(models.map((model) => model.label), <String>[
      'Gemini 3.6 Flash (High)',
      'Gemini 3.1 Pro (Low)',
      'Claude Opus 4.6 (Thinking)',
      'Gemini 3.5 Flash (Medium)',
    ]);
  });

  test(
    'generates commit message with agy using its configured model',
    () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-assist',
        )
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/foo.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
              added: 2,
              removed: 1,
            ),
          ],
        )
        ..gitDiffResult = const GitDiffResult(
          files: <GitDiffFile>[
            GitDiffFile(
              path: 'lib/foo.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
              lines: <GitDiffLine>[GitDiffLine.addition('+new line')],
            ),
          ],
        );
      final runner = _FakeProcessRunner(stdout: 'feat: add ai assist\n');
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
      );

      final result = await service.generate(
        const AiAssistRequest(
          operation: AiAssistOperation.commitMessage,
          workspacePath: '/repo',
          settings: AiAssistSettings(agent: AiAssistAgent.agy),
        ),
      );

      expect(result.text, 'feat: add ai assist');
      expect(runner.executable, 'agy');
      expect(runner.arguments, containsAll(<String>['--print', '--sandbox']));
      expect(runner.arguments, isNot(contains('--model')));
      expect(runner.stdinText, contains('feature/ai-assist'));
      expect(runner.stdinClosed, isTrue);
    },
  );

  test('passes an explicit agy model id unchanged', () async {
    final git = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'feature/ai-assist',
      )
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/foo.dart',
            area: GitChangeArea.staged,
            status: GitChangeStatus.modified,
          ),
        ],
      );
    final runner = _FakeProcessRunner(stdout: 'feat: add ai assist\n');
    final service = CliAiAssistService(gitBackend: git, processRunner: runner);

    await service.generate(
      const AiAssistRequest(
        operation: AiAssistOperation.commitMessage,
        workspacePath: '/repo',
        settings: AiAssistSettings(
          agent: AiAssistAgent.agy,
          selectedModelByAgent: <AiAssistAgent, String>{
            AiAssistAgent.agy: 'gemini-3.1-pro-low',
          },
        ),
      ),
    );

    expect(
      runner.arguments,
      containsAll(<String>['--model', 'gemini-3.1-pro-low']),
    );
  });

  test('discovers dynamic models through the agent CLI', () async {
    final runner = _FakeProcessRunner(
      stdout: '''
gemini-3.6-flash-high
gemini-3.1-pro-low
''',
    );
    final service = CliAiAssistModelDiscoveryService(processRunner: runner);

    final result = await service.discover(AiAssistAgent.agy);

    expect(result.success, isTrue);
    expect(result.defaultModelId, isNull);
    expect(result.models.map((model) => model.id), <String>[
      'gemini-3.6-flash-high',
      'gemini-3.1-pro-low',
    ]);
    expect(runner.executable, 'agy');
    expect(runner.arguments, <String>['models']);
  });

  test('discovers dynamic models with resolved command environment', () async {
    final runner = _FakeProcessRunner(stdout: 'gemini-3.6-flash-high\n');
    final service = CliAiAssistModelDiscoveryService(
      processRunner: runner,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
        value: <String, String>{'PATH': '/shell/bin:/usr/bin'},
      ),
    );

    await service.discover(AiAssistAgent.agy);

    expect(runner.environment, containsPair('PATH', '/shell/bin:/usr/bin'));
  });
}
