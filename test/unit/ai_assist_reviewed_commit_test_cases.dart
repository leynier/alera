part of 'ai_assist_service_test.dart';

void _registerReviewedCommitTests() {
  test(
    'reviewed files replace the staged context without staging anything',
    () async {
      final git = FakeGitBackend();
      final runner = _FakeProcessRunner(stdout: 'fix: selected files\n');
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
        commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(),
      );
      var started = false;
      await service.generate(
        AiAssistRequest(
          operation: .commitMessage,
          workspacePath: '/repo',
          settings: const AiAssistSettings(agent: .opencode),
          commitContext: const AiAssistCommitContext(
            branch: 'feature',
            stagedSummary: 'selected.txt',
            stagedPatch: '+selected only',
          ),
          onStarted: () => started = true,
        ),
      );
      expect(started, isTrue);
      expect(runner.stdinText, contains('selected.txt'));
      expect(runner.stdinText, contains('+selected only'));
      expect(git.calls, isEmpty);
    },
  );
}
