part of 'ai_text_generation_service_test.dart';

void _registerAiTextReadingDiffLifecycleTests() {
  test('waits for a timed-out process before deleting task files', () async {
    final exit = Completer<int>();
    final process = _FakeProcessRunner(
      stdout: '',
      exitCodeCompleter: exit,
      completeExitOnKill: false,
    );
    final runner = CliAiTextAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
    );
    final run = runner.run(
      const AiTextAgentRunRequest(
        settings: AiTextGenerationSettings(timeoutSeconds: 0),
        prompt: 'Plan this diff.',
        runId: 'reading-diff-timeout-cleanup',
        workingDirectory: '/repo',
        agent: AiTextGenerationAgent.codex,
        accessPolicy: AgentTaskAccessPolicy.diffOnly,
        outputContract: AgentTaskOutputContract.readingDiffPlanV1,
        outputSchema: '{"type":"object"}',
      ),
    );

    await untilCalled(() => process.killed);
    final isolatedDirectory = process.workingDirectory!;
    final schemaPath =
        process.arguments[process.arguments.indexOf('--output-schema') + 1];
    final promptDirectory = File(schemaPath).parent.path;
    expect(Directory(isolatedDirectory).existsSync(), isTrue);
    expect(Directory(promptDirectory).existsSync(), isTrue);
    exit.complete(143);
    await expectLater(run, throwsA(isA<AiTextGenerationException>()));
    expect(Directory(isolatedDirectory).existsSync(), isFalse);
    expect(Directory(promptDirectory).existsSync(), isFalse);
  });

  test(
    'waits for a startup-canceled process before deleting task files',
    () async {
      final startReturnGate = Completer<void>();
      final exit = Completer<int>();
      final process = _FakeProcessRunner(
        stdout: '',
        exitCodeCompleter: exit,
        completeExitOnKill: false,
        startReturnGate: startReturnGate,
      );
      final runner = CliAiTextAgentRunner(
        processRunner: process,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );
      final run = runner.run(
        const AiTextAgentRunRequest(
          settings: AiTextGenerationSettings(),
          prompt: 'Plan this diff.',
          runId: 'reading-diff-startup-cancel-cleanup',
          workingDirectory: '/repo',
          agent: AiTextGenerationAgent.codex,
          accessPolicy: AgentTaskAccessPolicy.diffOnly,
          outputContract: AgentTaskOutputContract.readingDiffPlanV1,
          outputSchema: '{"type":"object"}',
        ),
      );

      await untilCalled(() => process.startCount == 1);
      runner.cancel('reading-diff-startup-cancel-cleanup');
      startReturnGate.complete();
      await untilCalled(() => process.killed);
      final isolatedDirectory = process.workingDirectory!;
      final schemaPath =
          process.arguments[process.arguments.indexOf('--output-schema') + 1];
      final promptDirectory = File(schemaPath).parent.path;
      expect(Directory(isolatedDirectory).existsSync(), isTrue);
      expect(Directory(promptDirectory).existsSync(), isTrue);
      exit.complete(143);
      await expectLater(run, throwsA(isA<AiTextGenerationCanceledException>()));
      expect(Directory(isolatedDirectory).existsSync(), isFalse);
      expect(Directory(promptDirectory).existsSync(), isFalse);
    },
  );
}
