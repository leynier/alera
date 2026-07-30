part of 'ai_text_generation_service_test.dart';

void _registerAiTextPromptOverrideTests() {
  test('uses the agent and model configured for the prompt', () async {
    final git = FakeGitBackend()
      ..gitRepositoryStateResult = const GitRepositoryState(
        branch: 'feature/prompt-agent',
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
    final runner = _FakeProcessRunner(stdout: 'fix: use prompt agent\n');
    final service = CliAiTextGenerationService(
      gitBackend: git,
      processRunner: runner,
    );

    await service.generate(
      const AiTextGenerationRequest(
        operation: AiTextGenerationOperation.commitMessage,
        workspacePath: '/repo',
        settings: AiTextGenerationSettings(
          agent: AiTextGenerationAgent.agy,
          promptSettingsByOperation:
              <AiTextGenerationOperation, AiTextGenerationPromptSettings>{
                AiTextGenerationOperation.commitMessage:
                    AiTextGenerationPromptSettings(
                      agent: AiTextGenerationAgent.amp,
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
