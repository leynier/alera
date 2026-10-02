part of 'ai_assist_service_test.dart';

void _registerAiAssistReadingDiffLifecycleTests() {
  test('kills and reaps a live process before invalid UTF-8 escapes', () async {
    var stdoutCanceled = false;
    var stderrCanceled = false;
    final stdout = StreamController<List<int>>(
      sync: true,
      onCancel: () => stdoutCanceled = true,
    );
    final stderr = StreamController<List<int>>(
      sync: true,
      onCancel: () => stderrCanceled = true,
    );
    addTearDown(() async {
      await stdout.close();
      await stderr.close();
    });
    final exit = Completer<int>();
    final process = _FakeProcessRunner(
      stdout: '',
      stdoutStream: stdout.stream,
      stderrStream: stderr.stream,
      exitCodeCompleter: exit,
    );
    final runner = CliAiAssistAgentRunner(
      processRunner: process,
      commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
    );

    final run = runner.run(
      const AiAssistAgentRunRequest(
        settings: AiAssistSettings(),
        prompt: 'Plan this diff.',
        runId: 'invalid-utf8-cleanup',
        workingDirectory: '/repo',
        agent: .codex,
      ),
    );
    stdout.add(<int>[0xff]);

    await expectLater(run, throwsA(isA<FormatException>()));
    expect(process.killed, isTrue);
    expect(exit.isCompleted, isTrue);
    expect(stdoutCanceled, isTrue);
    expect(stderrCanceled, isTrue);
  });

  test(
    'kills and reaps a live process before a stream error escapes',
    () async {
      var stdoutCanceled = false;
      var stderrCanceled = false;
      final stdout = StreamController<List<int>>(
        sync: true,
        onCancel: () => stdoutCanceled = true,
      );
      final stderr = StreamController<List<int>>(
        sync: true,
        onCancel: () => stderrCanceled = true,
      );
      addTearDown(() async {
        await stdout.close();
        await stderr.close();
      });
      final exit = Completer<int>();
      final process = _FakeProcessRunner(
        stdout: '',
        stdoutStream: stdout.stream,
        stderrStream: stderr.stream,
        exitCodeCompleter: exit,
      );
      final runner = CliAiAssistAgentRunner(
        processRunner: process,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );

      final run = runner.run(
        const AiAssistAgentRunRequest(
          settings: AiAssistSettings(),
          prompt: 'Plan this diff.',
          runId: 'stream-error-cleanup',
          workingDirectory: '/repo',
          agent: .codex,
        ),
      );
      stdout.addError(StateError('broken agent output'));

      await expectLater(run, throwsA(isA<StateError>()));
      expect(process.killed, isTrue);
      expect(exit.isCompleted, isTrue);
      expect(stdoutCanceled, isTrue);
      expect(stderrCanceled, isTrue);
    },
  );

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
        agent: .codex,
        accessPolicy: .diffOnly,
        outputContract: .readingDiffPlanV1,
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
          agent: .codex,
          accessPolicy: .diffOnly,
          outputContract: .readingDiffPlanV1,
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
