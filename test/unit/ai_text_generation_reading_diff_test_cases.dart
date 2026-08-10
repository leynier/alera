part of 'ai_text_generation_service_test.dart';

void _registerAiTextReadingDiffTests() {
  test('runs Codex with a schema and reads its structured result file', () async {
    final process = _FakeProcessRunner(
      stdout:
          '{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}',
    );
    final runner = CliAiTextAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
    );

    final result = await runner.run(
      const AiTextAgentRunRequest(
        settings: AiTextGenerationSettings(),
        prompt: 'Plan this diff.',
        runId: 'reading-diff-codex',
        workingDirectory: '/repo',
        agent: AiTextGenerationAgent.codex,
        outputContract: AgentTaskOutputContract.readingDiffPlanV1,
        outputSchema: '{"type":"object"}',
      ),
    );

    expect(process.arguments, contains('--output-schema'));
    expect(process.arguments, contains('--output-last-message'));
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
        outputContract: AgentTaskOutputContract.readingDiffPlanV1,
        outputSchema: '{"type":"object"}',
      ),
    );

    expect(process.arguments, contains('--json-schema'));
    expect(process.arguments, contains('--no-session-persistence'));
    expect(
      process.arguments
          .skip(process.arguments.indexOf('--output-format') + 1)
          .first,
      'json',
    );
    expect(jsonDecode(result.text), containsPair('version', 1));
  });

  test('uses native JSON schema support for Antigravity and Grok', () async {
    for (final agent in const <AiTextGenerationAgent>[
      AiTextGenerationAgent.agy,
      AiTextGenerationAgent.grok,
    ]) {
      final process = _FakeProcessRunner(
        stdout:
            '{"version":1,"remove":[],"replace":[],"fold":[],"summary":"Keep behavior."}',
      );
      final runner = CliAiTextAgentRunner(
        processRunner: process,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );

      final result = await runner.run(
        AiTextAgentRunRequest(
          settings: const AiTextGenerationSettings(),
          prompt: 'Plan this diff.',
          runId: 'reading-diff-${agent.key}',
          workingDirectory: '/repo',
          agent: agent,
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
    }
  });

  test(
    'uses prompt JSON fallback for other AI Text agents in diff-only isolation',
    () async {
      final fallbackAgents = AiTextGenerationAgent.values.where(
        (agent) =>
            agent != AiTextGenerationAgent.codex &&
            agent != AiTextGenerationAgent.claude &&
            agent != AiTextGenerationAgent.agy &&
            agent != AiTextGenerationAgent.grok,
      );
      for (final agent in fallbackAgents) {
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
            settings: agent == AiTextGenerationAgent.custom
                ? const AiTextGenerationSettings(customCommand: 'custom-agent')
                : const AiTextGenerationSettings(),
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
        expect(process.workingDirectory, isNot('/repo'));
        expect(Directory(process.workingDirectory!).existsSync(), isFalse);
        expect(jsonDecode(result.text), containsPair('version', 1));
      }
    },
  );
}
