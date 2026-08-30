import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_diff_only_execution.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_prompt.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_service.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_model_discovery_service.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'fake_git_backend.dart';

part 'ai_assist_grok_test_cases.dart';
part 'ai_assist_fx_test_cases.dart';
part 'ai_assist_agy_test_cases.dart';
part 'ai_assist_reading_diff_test_cases.dart';
part 'ai_assist_reading_diff_lifecycle_test_cases.dart';
part 'ai_assist_prompt_override_test_cases.dart';
part 'ai_assist_test_harness.dart';

void main() {
  group('AI Assist', () {
    _registerGrokAiAssistTests();
    _registerFxAiAssistTests();
    _registerAgyAiAssistTests();
    _registerAiAssistReadingDiffTests();
    _registerAiAssistReadingDiffLifecycleTests();
    _registerAiAssistPromptOverrideTests();

    test('builds commit prompts with staged context and instructions', () {
      final prompt = buildCommitMessagePrompt(
        context: const AiAssistCommitContext(
          branch: 'feature/ai-assist',
          stagedSummary: '- lib/foo.dart (+2 -1)',
          stagedPatch: '+new line',
        ),
        customInstructions: 'Use conventional commits.',
      );

      expect(prompt, contains('Branch: feature/ai-assist'));
      expect(prompt, contains('Staged files:'));
      expect(prompt, contains('+new line'));
      expect(prompt, contains('Use conventional commits.'));
    });

    test('builds pull request prompts with range context and instructions', () {
      final prompt = buildPullRequestDetailsPrompt(
        context: const AiAssistPullRequestContext(
          baseBranch: 'main',
          headBranch: 'feature/ai-pr',
          commitSummary: '- abc1234 feat: add ai pr',
          fileSummary: '- M lib/foo.dart (+2 -1)',
          patch: '+new line',
        ),
        customInstructions: 'Prefer conventional titles.',
      );

      expect(prompt, contains('Base branch: main'));
      expect(prompt, contains('Head branch: feature/ai-pr'));
      expect(prompt, contains('feat: add ai pr'));
      expect(prompt, contains('+new line'));
      expect(prompt, contains('Prefer conventional titles.'));
    });

    test('parses generated pull request title and body', () {
      final details = parseGeneratedPullRequestDetails('''
Generating...
```text
feat: ship pull request ai

- Add title and description generation
- Reuse range context from git
```
''');

      expect(details.title, 'feat: ship pull request ai');
      expect(details.body, contains('Add title and description generation'));
    });

    test('cleans fenced commit output and caps subject length', () {
      final message = cleanGeneratedCommitMessage('''
Generating...
```text
${List<String>.filled(90, 'a').join()}.

Body line.
```
''');

      expect(message.split('\n').first.length, 72);
      expect(message, contains('Body line.'));
    });

    test('generates pull request details from base range context', () async {
      final git = FakeGitBackend()
        ..gitRangeContextResult = const GitRangeContext(
          baseRef: 'main',
          headBranch: 'feature/ai-pr',
          commits: <GitRangeCommit>[
            GitRangeCommit(
              oid: 'abcdef1',
              subject: 'feat: add pr ai',
              message: 'feat: add pr ai',
            ),
          ],
          files: <GitRangeFile>[
            GitRangeFile(
              path: 'lib/foo.dart',
              status: .modified,
              added: 2,
              removed: 1,
            ),
          ],
          patch: '+new line',
        );
      final runner = _FakeProcessRunner(
        stdout: 'feat: ship pr ai\n\n- Generate title and body\n',
      );
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
      );

      final result = await service.generate(
        const AiAssistRequest(
          operation: .pullRequestDetails,
          workspacePath: '/repo',
          settings: AiAssistSettings(agent: .agy),
          baseBranch: 'main',
          headBranch: 'feature/ai-pr',
        ),
      );

      expect(result.text, contains('feat: ship pr ai'));
      expect(runner.stdinText, contains('Base branch: main'));
      expect(runner.stdinText, contains('feat: add pr ai'));
      expect(runner.stdinText, contains('+new line'));
      expect(git.calls.any((call) => call.method == 'rangeContext'), isTrue);
    });

    test('rejects pull request generation without a base branch', () async {
      final service = CliAiAssistService(
        gitBackend: FakeGitBackend(),
        processRunner: _FakeProcessRunner(stdout: 'unused'),
      );

      await expectLater(
        service.generate(
          const AiAssistRequest(
            operation: .pullRequestDetails,
            workspacePath: '/repo',
            settings: AiAssistSettings(agent: .agy),
          ),
        ),
        throwsA(
          isA<AiAssistException>().having(
            (error) => error.message,
            'message',
            contains('base branch'),
          ),
        ),
      );
    });

    test(
      'starts commit message agents with resolved command environment',
      () async {
        final git = FakeGitBackend()
          ..gitRepositoryStateResult = const GitRepositoryState(
            branch: 'feature/ai-assist',
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
        final runner = _FakeProcessRunner(stdout: 'feat: add ai assist\n');
        final service = CliAiAssistService(
          gitBackend: git,
          processRunner: runner,
          commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
            value: <String, String>{'PATH': '/shell/bin:/usr/bin'},
          ),
        );

        await service.generate(
          const AiAssistRequest(
            operation: .commitMessage,
            workspacePath: '/repo',
            settings: AiAssistSettings(agent: .agy),
          ),
        );

        expect(runner.environment, containsPair('PATH', '/shell/bin:/usr/bin'));
      },
    );

    test('generates commit message with amp without archived flag', () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-assist',
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
      final runner = _FakeProcessRunner(stdout: 'fix: update source control\n');
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
      );

      await service.generate(
        const AiAssistRequest(
          operation: .commitMessage,
          workspacePath: '/repo',
          settings: AiAssistSettings(agent: .amp),
        ),
      );

      expect(runner.executable, 'amp');
      expect(runner.arguments, contains('--execute'));
      expect(runner.arguments, isNot(contains('--archive')));
    });

    test('generates commit message with opencode using stdin', () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-assist',
        )
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/large.dart',
              area: .staged,
              status: .modified,
            ),
          ],
        )
        ..gitDiffResult = GitDiffResult(
          files: <GitDiffFile>[
            GitDiffFile(
              path: 'lib/large.dart',
              area: .staged,
              status: .modified,
              lines: <GitDiffLine>[
                GitDiffLine.addition(
                  '+${List<String>.filled(30000, 'x').join()}',
                ),
              ],
            ),
          ],
        );
      final runner = _FakeProcessRunner(stdout: 'feat: handle large diff\n');
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
      );

      final result = await service.generate(
        const AiAssistRequest(
          operation: .commitMessage,
          workspacePath: '/repo',
          settings: AiAssistSettings(agent: .opencode),
        ),
      );

      expect(result.text, 'feat: handle large diff');
      expect(runner.executable, 'opencode');
      expect(
        runner.arguments,
        containsAll(<String>['run', '--agent', 'build']),
      );
      expect(runner.arguments, isNot(contains(runner.stdinText)));
      expect(runner.stdinText, contains('lib/large.dart'));
      expect(runner.stdinClosed, isTrue);
    });

    test('discovers pi models from stderr on successful exit', () async {
      final runner = _FakeProcessRunner(
        stdout: '',
        stderr: '''
provider        model                   context  max-out  thinking  images
github-copilot  gpt-5.4-mini            400K     128K     yes       yes
openai-codex    gpt-5.5                 272K     128K     yes       yes
''',
      );
      final service = CliAiAssistModelDiscoveryService(processRunner: runner);

      final result = await service.discover(.pi);

      expect(result.success, isTrue);
      expect(result.models.map((model) => model.id), <String>[
        'github-copilot/gpt-5.4-mini',
        'openai-codex/gpt-5.5',
      ]);
    });

    test('returns static models without spawning for static agents', () async {
      final runner = _FakeProcessRunner(stdout: 'unused');
      final service = CliAiAssistModelDiscoveryService(processRunner: runner);

      final result = await service.discover(.amp);

      expect(result.success, isTrue);
      expect(result.defaultModelId, 'smart');
      expect(runner.started, isFalse);
    });

    test(
      'falls back to static models when discovery returns no models',
      () async {
        final runner = _FakeProcessRunner(stdout: 'unparseable output');
        final service = CliAiAssistModelDiscoveryService(processRunner: runner);

        final result = await service.discover(.cursor);

        expect(result.success, isTrue);
        expect(result.defaultModelId, 'auto');
        expect(result.models.map((model) => model.id), <String>['auto']);
      },
    );

    test('surfaces model discovery failures with safe detail', () async {
      final runner = _FakeProcessRunner(
        stdout: '',
        stderr: 'auth expired',
        exitCode: 1,
      );
      final service = CliAiAssistModelDiscoveryService(processRunner: runner);

      final result = await service.discover(.agy);

      expect(result.success, isFalse);
      expect(result.error, 'Antigravity model discovery failed: auth expired');
    });

    test('reports no staged changes before starting an agent', () async {
      final runner = _FakeProcessRunner(stdout: 'unused');
      final service = CliAiAssistService(
        gitBackend: FakeGitBackend(),
        processRunner: runner,
      );

      await expectLater(
        service.generate(
          const AiAssistRequest(
            operation: .commitMessage,
            workspacePath: '/repo',
            settings: AiAssistSettings(),
          ),
        ),
        throwsA(
          isA<AiAssistException>().having(
            (error) => error.message,
            'message',
            'No staged changes to summarize.',
          ),
        ),
      );
      expect(runner.started, isFalse);
    });

    test('surfaces agent stderr on failure', () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-assist',
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
      final runner = _FakeProcessRunner(
        stdout: '',
        stderr: 'model is not available',
        exitCode: 1,
      );
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
      );

      await expectLater(
        service.generate(
          const AiAssistRequest(
            operation: .commitMessage,
            workspacePath: '/repo',
            settings: AiAssistSettings(agent: .agy),
          ),
        ),
        throwsA(
          isA<AiAssistException>().having(
            (error) => error.message,
            'message',
            'Antigravity failed: model is not available',
          ),
        ),
      );
    });

    test(
      'throws a cancellation exception when a running lane is canceled',
      () async {
        final git = FakeGitBackend()
          ..gitRepositoryStateResult = const GitRepositoryState(
            branch: 'feature/ai-assist',
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
        final exitCode = Completer<int>();
        final runner = _FakeProcessRunner(
          stdout: '',
          exitCodeCompleter: exitCode,
        );
        final service = CliAiAssistService(
          gitBackend: git,
          processRunner: runner,
        );

        final generation = service.generate(
          const AiAssistRequest(
            operation: .commitMessage,
            workspacePath: '/repo',
            settings: AiAssistSettings(agent: .agy),
          ),
        );
        await untilCalled(() => runner.started);

        service.cancel('/repo', .commitMessage);

        await expectLater(
          generation,
          throwsA(isA<AiAssistCanceledException>()),
        );
        expect(runner.killed, isTrue);
      },
    );

    test('keeps a canceled running lane reserved until process exit', () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-assist',
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
      final exitCode = Completer<int>();
      final runner = _FakeProcessRunner(
        stdout: '',
        exitCodeCompleter: exitCode,
        completeExitOnKill: false,
      );
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
      );

      final generation = service.generate(
        const AiAssistRequest(
          operation: .commitMessage,
          workspacePath: '/repo',
          settings: AiAssistSettings(agent: .agy),
        ),
      );
      await untilCalled(() => runner.started);

      service.cancel('/repo', .commitMessage);

      await expectLater(
        service.generate(
          const AiAssistRequest(
            operation: .commitMessage,
            workspacePath: '/repo',
            settings: AiAssistSettings(agent: .agy),
          ),
        ),
        throwsA(
          isA<AiAssistException>().having(
            (error) => error.message,
            'message',
            'Generation is already running.',
          ),
        ),
      );
      expect(runner.startCount, 1);

      exitCode.complete(143);
      await expectLater(generation, throwsA(isA<AiAssistCanceledException>()));
    });

    test('honors cancellation before the agent process starts', () async {
      final git = _DelayedDiffGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-assist',
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
      final runner = _FakeProcessRunner(stdout: 'unused');
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
      );

      final generation = service.generate(
        const AiAssistRequest(
          operation: .commitMessage,
          workspacePath: '/repo',
          settings: AiAssistSettings(agent: .agy),
        ),
      );
      await untilCalled(() => git.diffStarted);

      service.cancel('/repo', .commitMessage);
      git.completeDiff();

      await expectLater(generation, throwsA(isA<AiAssistCanceledException>()));
      expect(runner.started, isFalse);
    });

    test('rejects oversized prompts for argv agents before starting', () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-assist',
        )
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/foo.dart',
              area: .staged,
              status: .modified,
            ),
          ],
        )
        ..gitDiffResult = GitDiffResult(
          files: <GitDiffFile>[
            GitDiffFile(
              path: 'lib/foo.dart',
              area: .staged,
              status: .modified,
              lines: <GitDiffLine>[
                GitDiffLine.addition(
                  '+${List<String>.filled(30000, 'x').join()}',
                ),
              ],
            ),
          ],
        );
      final runner = _FakeProcessRunner(stdout: 'unused');
      final service = CliAiAssistService(
        gitBackend: git,
        processRunner: runner,
      );

      await expectLater(
        service.generate(
          const AiAssistRequest(
            operation: .commitMessage,
            workspacePath: '/repo',
            settings: AiAssistSettings(agent: .copilot),
          ),
        ),
        throwsA(
          isA<AiAssistException>().having(
            (error) => error.message,
            'message',
            contains('cannot receive large prompts safely'),
          ),
        ),
      );
      expect(runner.started, isFalse);
    });
  });
}
