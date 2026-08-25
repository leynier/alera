part of 'ai_assist_service_test.dart';

void _registerAiAssistReadingDiffLifecycleTests() {
  test('waits for a timed-out process before deleting task files', () async {
    final exit = Completer<int>();
    final process = _FakeProcessRunner(
      stdout: '',
      exitCodeCompleter: exit,
      completeExitOnKill: false,
    );
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
    );
    final run = runner.run(
      const AiAssistAgentRunRequest(
        settings: AiAssistSettings(timeoutSeconds: 0),
        prompt: 'Plan this diff.',
        runId: 'reading-diff-timeout-cleanup',
        workingDirectory: '/repo',
        agent: AiAssistAgent.codex,
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
    await expectLater(run, throwsA(isA<AiAssistException>()));
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
      final runner = CliAiAssistAgentRunner(
        processRunner: process,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );
      final run = runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(),
          prompt: 'Plan this diff.',
          runId: 'reading-diff-startup-cancel-cleanup',
          workingDirectory: '/repo',
          agent: AiAssistAgent.codex,
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
      await expectLater(run, throwsA(isA<AiAssistCanceledException>()));
      expect(Directory(isolatedDirectory).existsSync(), isFalse);
      expect(Directory(promptDirectory).existsSync(), isFalse);
    },
  );
}
