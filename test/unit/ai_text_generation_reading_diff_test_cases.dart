part of 'ai_text_generation_service_test.dart';

void _registerAiTextReadingDiffTests() {
  test('falls back to Codex for an unsupported inherited reading agent', () {
    expect(
      readingDiffAgentForSettings(
        const AiTextGenerationSettings(agent: AiTextGenerationAgent.cursor),
      ),
      AiTextGenerationAgent.codex,
    );
    expect(
      readingDiffAgentForSettings(
        const AiTextGenerationSettings(
          agent: AiTextGenerationAgent.cursor,
          promptSettingsByOperation:
              <AiTextGenerationOperation, AiTextGenerationPromptSettings>{
                AiTextGenerationOperation.readingDiff:
                    AiTextGenerationPromptSettings(
                      agent: AiTextGenerationAgent.claude,
                    ),
              },
        ),
      ),
      AiTextGenerationAgent.claude,
    );
  });

  test('runs Codex with a schema and reads its structured result file', () async {
    final process = _FakeProcessRunner(
      stdout:
          '{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}',
    );
    final runner = CliAiTextAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
        value: <String, String>{
          'PATH': '/usr/bin',
          'CODEX_HOME': '/codex-home',
          'OPENAI_API_KEY': 'must-not-leak',
        },
      ),
    );

    final result = await runner.run(
      const AiTextAgentRunRequest(
        settings: AiTextGenerationSettings(),
        prompt: 'Plan this diff.',
        runId: 'reading-diff-codex',
        workingDirectory: '/repo',
        agent: AiTextGenerationAgent.codex,
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
    expect(process.environment, isNot(contains('OPENAI_API_KEY')));
    expect(process.includeParentEnvironment, isFalse);
    expect(process.outputSchemaText, '{"type":"object"}');
    expect(result.text, contains('"version":1'));
  });

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
    final runner = CliAiTextAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
    );

    await expectLater(
      runner.run(
        const AiTextAgentRunRequest(
          settings: AiTextGenerationSettings(),
          prompt: 'Plan this diff.',
          runId: 'reading-diff-codex-error',
          workingDirectory: '/repo',
          agent: AiTextGenerationAgent.codex,
          outputContract: AgentTaskOutputContract.readingDiffPlanV1,
          outputSchema: '{"type":"object"}',
        ),
      ),
      throwsA(
        isA<AiTextGenerationException>().having(
          (error) => error.message,
          'message',
          'Codex failed: The version property must declare an integer type.',
        ),
      ),
    );
  });

  test('unwraps Claude structured output and disables persistence', () async {
    final process = _FakeProcessRunner(
      stdout:
          '{"structured_output":{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}}',
    );
    final runner = CliAiTextAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
    );

    final result = await runner.run(
      const AiTextAgentRunRequest(
        settings: AiTextGenerationSettings(),
        prompt: 'Plan this diff.',
        runId: 'reading-diff-claude',
        workingDirectory: '/repo',
        agent: AiTextGenerationAgent.claude,
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
    final runner = CliAiTextAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: _FakeCommandEnvironmentResolver(
        value: <String, String>{'PATH': '/usr/bin', 'HOME': userHome.path},
      ),
    );

    final result = await runner.run(
      const AiTextAgentRunRequest(
        settings: AiTextGenerationSettings(),
        prompt: 'Plan this diff.',
        runId: 'reading-diff-grok',
        workingDirectory: '/repo',
        agent: AiTextGenerationAgent.grok,
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

  test('uses prompt JSON fallback for tool-free AI Text agents', () async {
    for (final agent in const <AiTextGenerationAgent>[
      AiTextGenerationAgent.copilot,
      AiTextGenerationAgent.pi,
    ]) {
      final process = _FakeProcessRunner(
        stdout:
            'Generating...\n```json\n{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}\n```',
      );
      final runner = CliAiTextAgentRunner(
        processRunner: process,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );

      final result = await runner.run(
        AiTextAgentRunRequest(
          settings: const AiTextGenerationSettings(),
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
      if (agent == AiTextGenerationAgent.copilot) {
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
    for (final agent in const <AiTextGenerationAgent>[
      AiTextGenerationAgent.custom,
      AiTextGenerationAgent.cursor,
      AiTextGenerationAgent.agy,
      AiTextGenerationAgent.opencode,
      AiTextGenerationAgent.opencode2,
      AiTextGenerationAgent.amp,
    ]) {
      final process = _FakeProcessRunner(stdout: 'unused');
      final runner = CliAiTextAgentRunner(
        processRunner: process,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );

      await expectLater(
        runner.run(
          AiTextAgentRunRequest(
            settings: const AiTextGenerationSettings(
              customCommand: 'custom-agent',
            ),
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
          isA<AiTextGenerationException>().having(
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
    final runner = CliAiTextAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
    );

    await expectLater(
      runner.run(
        const AiTextAgentRunRequest(
          settings: AiTextGenerationSettings(),
          prompt: 'Plan this diff.',
          runId: 'reading-diff-stderr',
          workingDirectory: '/repo',
          agent: AiTextGenerationAgent.codex,
          accessPolicy: AgentTaskAccessPolicy.diffOnly,
          outputContract: AgentTaskOutputContract.readingDiffPlanV1,
          outputSchema: '{"type":"object"}',
        ),
      ),
      throwsA(
        isA<AiTextGenerationException>().having(
          (error) => error.message,
          'message',
          'Codex failed: subscription quota exceeded',
        ),
      ),
    );
  });
}
