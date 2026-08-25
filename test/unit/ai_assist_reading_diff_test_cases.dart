part of 'ai_assist_service_test.dart';

void _registerAiAssistReadingDiffTests() {
  test('falls back to Codex for an unsupported inherited reading agent', () {
    expect(
      readingDiffAgentForSettings(
        const AiAssistSettings(agent: AiAssistAgent.cursor),
      ),
      AiAssistAgent.codex,
    );
    expect(
      readingDiffAgentForSettings(
        const AiAssistSettings(
          agent: AiAssistAgent.cursor,
          promptSettingsByOperation:
              <AiAssistOperation, AiAssistPromptSettings>{
                AiAssistOperation.readingDiff: AiAssistPromptSettings(
                  agent: AiAssistAgent.claude,
                ),
              },
        ),
      ),
      AiAssistAgent.claude,
    );
    const settings = AiAssistSettings(
      agent: AiAssistAgent.cursor,
      selectedModelByAgent: <AiAssistAgent, String>{
        AiAssistAgent.cursor: 'cursor-composer',
        AiAssistAgent.codex: 'gpt-codex',
      },
    );
    expect(
      readingDiffModelForSettings(
        settings,
        readingDiffAgentForSettings(settings),
      ),
      'gpt-codex',
    );
    expect(
      aiAssistAgentsForModelDiscovery(settings, const <AiAssistOperation>[
        AiAssistOperation.commitMessage,
        AiAssistOperation.readingDiff,
      ]),
      <AiAssistAgent>{AiAssistAgent.cursor, AiAssistAgent.codex},
    );
  });

  test('runs Codex with a schema and reads its structured result file', () async {
    final process = _FakeProcessRunner(
      stdout:
          '{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}',
    );
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
        value: <String, String>{
          'PATH': '/usr/bin',
          'CODEX_HOME': '/codex-home',
          'HTTPS_PROXY': 'http://proxy.example',
          'no_proxy': 'localhost',
          'OPENAI_API_KEY': 'must-not-leak',
        },
      ),
    );

    final result = await runner.run(
      const AiAssistAgentRunRequest(
        settings: AiAssistSettings(),
        prompt: 'Plan this diff.',
        runId: 'reading-diff-codex',
        workingDirectory: '/repo',
        agent: AiAssistAgent.codex,
        accessPolicy: AgentTaskAccessPolicy.diffOnly,
        outputContract: AgentTaskOutputContract.readingDiffPlanV1,
        outputSchema: '{"type":"object"}',
      ),
    );

    expect(process.arguments, contains('--output-schema'));
    expect(process.arguments, contains('--output-last-message'));
    expect(process.arguments, contains('--ignore-user-config'));
    expect(
      process.arguments,
      contains('default_permissions="alera_diff_only"'),
    );
    expect(process.arguments, isNot(contains('-s')));
    expect(process.environment, containsPair('CODEX_HOME', '/codex-home'));
    expect(
      process.environment,
      containsPair('HTTPS_PROXY', 'http://proxy.example'),
    );
    expect(process.environment, containsPair('no_proxy', 'localhost'));
    expect(process.environment, isNot(contains('OPENAI_API_KEY')));
    expect(process.includeParentEnvironment, isFalse);
    expect(process.outputSchemaText, '{"type":"object"}');
    expect(result.text, contains('"version":1'));
  });

  test(
    'preserves Codex keyring authentication in the isolated process',
    () async {
      final codexHome = await Directory.systemTemp.createTemp(
        'alera-codex-keyring-',
      );
      addTearDown(() => codexHome.delete(recursive: true));
      await File(
        p.join(codexHome.path, 'config.toml'),
      ).writeAsString('cli_auth_credentials_store = "keyring"\n');
      final process = _FakeProcessRunner(
        stdout:
            '{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}',
      );
      final runner = CliAiAssistAgentRunner(
        processRunner: process,
        commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
          value: <String, String>{
            'PATH': '/usr/bin',
            'CODEX_HOME': codexHome.path,
            'DBUS_SESSION_BUS_ADDRESS': 'unix:path=/run/user/1000/bus',
            'XDG_RUNTIME_DIR': '/run/user/1000',
            'OPENAI_API_KEY': 'must-not-leak',
          },
        ),
      );

      await runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(),
          prompt: 'Plan this diff.',
          runId: 'reading-diff-codex-keyring',
          workingDirectory: '/repo',
          agent: AiAssistAgent.codex,
          accessPolicy: AgentTaskAccessPolicy.diffOnly,
          outputContract: AgentTaskOutputContract.readingDiffPlanV1,
          outputSchema: '{"type":"object"}',
        ),
      );

      expect(
        process.arguments,
        contains('cli_auth_credentials_store="keyring"'),
      );
      expect(
        process.environment,
        containsPair(
          'DBUS_SESSION_BUS_ADDRESS',
          'unix:path=/run/user/1000/bus',
        ),
      );
      expect(
        process.environment,
        containsPair('XDG_RUNTIME_DIR', '/run/user/1000'),
      );
      expect(process.environment, isNot(contains('OPENAI_API_KEY')));
    },
  );

  test('extracts Codex message from a multiline JSON error', () async {
    final process = _FakeProcessRunner(
      stdout: '',
      stderr: '''
ERROR: {
  "type": "error",
  "error": {
    "type": "invalid_request_error",
    "code": "invalid_json_schema",
    "message": "The version property must declare an integer type.",
    "param": "text.format.schema"
  },
  "status": 400
}
''',
      exitCode: 1,
    );
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
    );

    await expectLater(
      runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(),
          prompt: 'Plan this diff.',
          runId: 'reading-diff-codex-error',
          workingDirectory: '/repo',
          agent: AiAssistAgent.codex,
          outputContract: AgentTaskOutputContract.readingDiffPlanV1,
          outputSchema: '{"type":"object"}',
        ),
      ),
      throwsA(
        isA<AiAssistException>().having(
          (error) => error.message,
          'message',
          'Codex failed: The version property must declare an integer type.',
        ),
      ),
    );
  });

  test('hydrates missing Codex variables before isolating the process', () async {
    final process = _FakeProcessRunner(
      stdout:
          '{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}',
    );
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
        variableValues: <String, String>{
          'CODEX_HOME': '/login-shell/codex',
          'HTTPS_PROXY': 'http://login-shell-proxy.example',
        },
      ),
    );

    await runner.run(
      const AiAssistAgentRunRequest(
        settings: AiAssistSettings(),
        prompt: 'Plan this diff.',
        runId: 'reading-diff-codex-hydrated',
        workingDirectory: '/repo',
        agent: AiAssistAgent.codex,
        accessPolicy: AgentTaskAccessPolicy.diffOnly,
        outputContract: AgentTaskOutputContract.readingDiffPlanV1,
        outputSchema: '{"type":"object"}',
      ),
    );

    expect(
      process.environment,
      containsPair('CODEX_HOME', '/login-shell/codex'),
    );
    expect(
      process.environment,
      containsPair('HTTPS_PROXY', 'http://login-shell-proxy.example'),
    );
    expect(process.includeParentEnvironment, isFalse);
  });

  test('unwraps Claude structured output and disables persistence', () async {
    final process = _FakeProcessRunner(
      stdout:
          '{"structured_output":{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}}',
    );
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
    );

    final result = await runner.run(
      const AiAssistAgentRunRequest(
        settings: AiAssistSettings(),
        prompt: 'Plan this diff.',
        runId: 'reading-diff-claude',
        workingDirectory: '/repo',
        agent: AiAssistAgent.claude,
        accessPolicy: AgentTaskAccessPolicy.diffOnly,
        outputContract: AgentTaskOutputContract.readingDiffPlanV1,
        outputSchema: '{"type":"object"}',
      ),
    );

    expect(process.arguments, contains('--json-schema'));
    expect(process.arguments, contains('--no-session-persistence'));
    expect(process.arguments, containsAll(<String>['--tools', '']));
    expect(
      process.arguments
          .skip(process.arguments.indexOf('--output-format') + 1)
          .first,
      'json',
    );
    expect(jsonDecode(result.text), containsPair('version', 1));
  });

  test('uses native JSON schema support for Grok', () async {
    final userHome = await Directory.systemTemp.createTemp(
      'alera-grok-reading-diff-home-',
    );
    addTearDown(() => userHome.delete(recursive: true));
    final grokHome = Directory('${userHome.path}/.grok');
    await grokHome.create();
    await File(
      '${grokHome.path}/auth.json',
    ).writeAsString('{"token":"test-token"}');
    await File(
      '${grokHome.path}/config.toml',
    ).writeAsString('[mcp]\nenabled = true');
    final process = _FakeProcessRunner(
      stdout:
          '{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}',
    );
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
        value: <String, String>{'PATH': '/usr/bin', 'HOME': userHome.path},
      ),
    );

    final result = await runner.run(
      const AiAssistAgentRunRequest(
        settings: AiAssistSettings(),
        prompt: 'Plan this diff.',
        runId: 'reading-diff-grok',
        workingDirectory: '/repo',
        agent: AiAssistAgent.grok,
        accessPolicy: AgentTaskAccessPolicy.diffOnly,
        outputContract: AgentTaskOutputContract.readingDiffPlanV1,
        outputSchema: '{"type":"object"}',
      ),
    );

    expect(process.arguments, contains('--json-schema'));
    expect(process.arguments, contains('{"type":"object"}'));
    expect(
      process.arguments
          .skip(process.arguments.indexOf('--output-format') + 1)
          .first,
      'json',
    );
    expect(jsonDecode(result.text), containsPair('version', 1));
    expect(process.grokAuthText, '{"token":"test-token"}');
    expect(process.grokConfigText, isNull);
  });

  test('uses prompt JSON fallback for tool-free AI Assist agents', () async {
    for (final agent in const <AiAssistAgent>[
      AiAssistAgent.copilot,
      AiAssistAgent.pi,
    ]) {
      final process = _FakeProcessRunner(
        stdout:
            'Generating...\n```json\n{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}\n```',
      );
      final runner = CliAiAssistAgentRunner(
        processRunner: process,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );

      final result = await runner.run(
        AiAssistAgentRunRequest(
          settings: const AiAssistSettings(),
          prompt: 'Plan this diff with the embedded schema.',
          runId: 'reading-diff-${agent.key}',
          workingDirectory: '/repo',
          agent: agent,
          accessPolicy: AgentTaskAccessPolicy.diffOnly,
          outputContract: AgentTaskOutputContract.readingDiffPlanV1,
          outputSchema: '{"type":"object"}',
        ),
      );

      expect(process.arguments, isNot(contains('--json-schema')));
      expect(process.arguments, isNot(contains('--output-schema')));
      if (agent == AiAssistAgent.copilot) {
        expect(process.arguments, contains('--available-tools='));
        expect(process.arguments, contains('--excluded-tools=*'));
      } else {
        expect(process.arguments, contains('--no-tools'));
      }
      expect(process.workingDirectory, isNot('/repo'));
      expect(Directory(process.workingDirectory!).existsSync(), isFalse);
      expect(jsonDecode(result.text), containsPair('version', 1));
    }
  });

  test('rejects agents that cannot guarantee diff-only access', () async {
    for (final agent in const <AiAssistAgent>[
      AiAssistAgent.custom,
      AiAssistAgent.cursor,
      AiAssistAgent.agy,
      AiAssistAgent.opencode,
      AiAssistAgent.opencode2,
      AiAssistAgent.amp,
    ]) {
      final process = _FakeProcessRunner(stdout: 'unused');
      final runner = CliAiAssistAgentRunner(
        processRunner: process,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );

      await expectLater(
        runner.run(
          AiAssistAgentRunRequest(
            settings: const AiAssistSettings(customCommand: 'custom-agent'),
            prompt: 'Plan this diff.',
            runId: 'reading-diff-rejected-${agent.key}',
            workingDirectory: '/repo',
            agent: agent,
            accessPolicy: AgentTaskAccessPolicy.diffOnly,
            outputContract: AgentTaskOutputContract.readingDiffPlanV1,
            outputSchema: '{"type":"object"}',
          ),
        ),
        throwsA(
          isA<AiAssistException>().having(
            (error) => error.message,
            'message',
            contains('cannot guarantee diff-only access'),
          ),
        ),
      );
      expect(process.started, isFalse);
    }
  });

  test('prefers stderr failure over a valid structured stdout plan', () async {
    final process = _FakeProcessRunner(
      stdout:
          '{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}',
      stderr: '{"error":{"message":"subscription quota exceeded"}}',
      exitCode: 1,
    );
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
    );

    await expectLater(
      runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(),
          prompt: 'Plan this diff.',
          runId: 'reading-diff-stderr',
          workingDirectory: '/repo',
          agent: AiAssistAgent.codex,
          accessPolicy: AgentTaskAccessPolicy.diffOnly,
          outputContract: AgentTaskOutputContract.readingDiffPlanV1,
          outputSchema: '{"type":"object"}',
        ),
      ),
      throwsA(
        isA<AiAssistException>().having(
          (error) => error.message,
          'message',
          'Codex failed: subscription quota exceeded',
        ),
      ),
    );
  });
}
