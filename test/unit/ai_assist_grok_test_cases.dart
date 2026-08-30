part of 'ai_assist_service_test.dart';

void _registerGrokAiAssistTests() {
  test('parses Grok Build models and exposes Grok Default effort', () {
    final models = parseGrokModels('''
You are logged in with grok.com.

Default model: grok-4.5

Available models:
  * grok-4.5 (default)
  - grok-composer-2.5-fast
''');

    expect(models.map((model) => model.id), <String>[
      'grok-4.5',
      'grok-composer-2.5-fast',
    ]);
    expect(models.first.defaultThinkingLevel, 'default');
    expect(models.first.thinkingLevels.first.label, 'Grok Default');
    expect(
      models.first.thinkingLevels.map((level) => level.id),
      containsAll(<String>['default', 'xhigh', 'max']),
    );
  });

  test(
    'generates Grok Build commit text from a temporary prompt file',
    () async {
      final userHome = await Directory.systemTemp.createTemp(
        'alera-grok-user-home-',
      );
      addTearDown(() => userHome.delete(recursive: true));
      final configuredGrokHome = Directory('${userHome.path}/.grok');
      await configuredGrokHome.create();
      await File('${configuredGrokHome.path}/auth.json')
          .writeAsString('{"token":"test-token"}');
      await File('${configuredGrokHome.path}/config.toml')
          .writeAsString('[models]\ndefault = "custom-model"');
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/grok-build',
        )
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/grok.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
            ),
          ],
        );
      final runner = _FakeProcessRunner(stdout: 'feat: add grok build\n');
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
        commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
          value: <String, String>{'PATH': '/usr/bin', 'HOME': userHome.path},
        ),
      );

      final result = await service.generate(
        const AiAssistRequest(
          operation: AiAssistOperation.commitMessage,
          workspacePath: '/repo',
          settings: AiAssistSettings(agent: AiAssistAgent.grok),
        ),
      );

      expect(result.text, 'feat: add grok build');
      expect(runner.executable, 'grok');
      expect(
        runner.arguments,
        containsAll(<String>[
          '--prompt-file',
          '--tools',
          '',
          '--no-subagents',
          '--disable-web-search',
          '--no-memory',
          '--max-turns',
          '1',
        ]),
      );
      expect(runner.arguments, isNot(contains('--effort')));
      expect(runner.promptFileText, contains('feature/grok-build'));
      expect(runner.stdinText, isEmpty);
      expect(runner.promptFilePath, isNotNull);
      expect(File(runner.promptFilePath!).existsSync(), isFalse);
      expect(runner.grokAuthText, '{"token":"test-token"}');
      expect(runner.grokConfigText, '[models]\ndefault = "custom-model"');
      expect(runner.grokHomePath, isNotNull);
      expect(Directory(runner.grokHomePath!).existsSync(), isFalse);
    },
  );

  test('passes explicit Grok Build reasoning effort', () async {
    final git = _grokGitBackend();
    final runner = _FakeProcessRunner(stdout: 'fix: use high effort\n');
    final service = CliAiAssistService(gitBackend: git, processRunner: runner);

    await service.generate(
      const AiAssistRequest(
        operation: AiAssistOperation.commitMessage,
        workspacePath: '/repo',
        settings: AiAssistSettings(
          agent: AiAssistAgent.grok,
          selectedThinkingByModel: <String, String>{'grok-4.6': 'high'},
        ),
      ),
    );

    expect(runner.arguments, containsAllInOrder(<String>['--effort', 'high']));
  });

  test('passes the reasoning effort configured for the operation', () async {
    final git = _grokGitBackend();
    final runner = _FakeProcessRunner(stdout: 'fix: use operation effort\n');
    final service = CliAiAssistService(gitBackend: git, processRunner: runner);

    await service.generate(
      const AiAssistRequest(
        operation: AiAssistOperation.commitMessage,
        workspacePath: '/repo',
        settings: AiAssistSettings(
          agent: AiAssistAgent.grok,
          selectedThinkingByOperation: <AiAssistOperation, Map<String, String>>{
            AiAssistOperation.commitMessage: <String, String>{
              'grok-4.6': 'high',
            },
          },
        ),
      ),
    );

    expect(runner.arguments, containsAllInOrder(<String>['--effort', 'high']));
  });

  test('passes Grok Build max reasoning effort', () async {
    final git = _grokGitBackend();
    final runner = _FakeProcessRunner(stdout: 'fix: use max effort\n');
    final service = CliAiAssistService(gitBackend: git, processRunner: runner);

    await service.generate(
      const AiAssistRequest(
        operation: AiAssistOperation.commitMessage,
        workspacePath: '/repo',
        settings: AiAssistSettings(
          agent: AiAssistAgent.grok,
          selectedThinkingByModel: <String, String>{'grok-4.6': 'max'},
        ),
      ),
    );

    expect(runner.arguments, containsAllInOrder(<String>['--effort', 'max']));
  });

  test('removes the Grok Build prompt file after CLI failure', () async {
    final runner = _FakeProcessRunner(
      stdout: '',
      stderr: 'authentication required',
      exitCode: 1,
    );
    final service = CliAiAssistService(
      gitBackend: _grokGitBackend(),
      processRunner: runner,
    );

    await expectLater(
      service.generate(
        const AiAssistRequest(
          operation: AiAssistOperation.commitMessage,
          workspacePath: '/repo',
          settings: AiAssistSettings(agent: AiAssistAgent.grok),
        ),
      ),
      throwsA(isA<AiAssistException>()),
    );

    expect(runner.promptFilePath, isNotNull);
    expect(File(runner.promptFilePath!).existsSync(), isFalse);
  });
}

FakeGitBackend _grokGitBackend() {
  return FakeGitBackend()
    ..gitRepositoryStateResult = const GitRepositoryState(branch: 'main')
    ..gitStatusResult = const GitStatusResult(
      entries: <GitChangeEntry>[
        GitChangeEntry(
          path: 'lib/grok.dart',
          area: GitChangeArea.staged,
          status: GitChangeStatus.modified,
        ),
      ],
    );
}
