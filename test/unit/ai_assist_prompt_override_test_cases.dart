part of 'ai_assist_service_test.dart';

void _registerAiAssistPromptOverrideTests() {
  test('uses the agent and model configured for the prompt', () async {
    final git = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'feature/prompt-agent',
      )
      ..gitStatusResult = const GitStatusResult(
        entries: <GitChangeEntry>[
          GitChangeEntry(
            path: 'lib/foo.dart',
            area: .staged,
            status: .modified,
          ),
        ],
      );
    final runner = _FakeProcessRunner(stdout: 'fix: use prompt agent\n');
    final service = CliAiAssistService(gitBackend: git, processRunner: runner);

    await service.generate(
      const AiAssistRequest(
        operation: .commitMessage,
        workspacePath: '/repo',
        settings: AiAssistSettings(
          agent: .agy,
          promptSettingsByOperation:
              <AiAssistOperation, AiAssistPromptSettings>{
                AiAssistOperation.commitMessage: AiAssistPromptSettings(
                  agent: .amp,
                  model: 'rush',
                ),
              },
        ),
      ),
    );

    expect(runner.executable, 'amp');
    expect(runner.arguments, containsAll(<String>['--mode', 'rush']));
  });
}
