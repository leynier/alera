import 'dart:async';
import 'dart:convert';

import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_prompt.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_service.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_model_discovery_service.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git_backend.dart';

void main() {
  group('AI text generation', () {
    test('builds commit prompts with staged context and instructions', () {
      final prompt = buildCommitMessagePrompt(
        context: const AiTextCommitContext(
          branch: 'feature/ai-text',
          stagedSummary: '- lib/foo.dart (+2 -1)',
          stagedPatch: '+new line',
        ),
        customInstructions: 'Use conventional commits.',
      );

      expect(prompt, contains('Branch: feature/ai-text'));
      expect(prompt, contains('Staged files:'));
      expect(prompt, contains('+new line'));
      expect(prompt, contains('Use conventional commits.'));
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

    test('parses agy model output as verbatim model ids', () {
      final models = parseLineModels('''
Gemini 3.5 Flash (Medium)
Claude Sonnet 4.6 (Thinking)
''');

      expect(models.map((model) => model.id), <String>[
        'Gemini 3.5 Flash (Medium)',
        'Claude Sonnet 4.6 (Thinking)',
      ]);
    });

    test('generates commit message with agy using stdin print mode', () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-text',
        )
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/foo.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
              added: 2,
              removed: 1,
            ),
          ],
        )
        ..gitDiffResult = const GitDiffResult(
          files: <GitDiffFile>[
            GitDiffFile(
              path: 'lib/foo.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
              lines: <GitDiffLine>[GitDiffLine.addition('+new line')],
            ),
          ],
        );
      final runner = _FakeProcessRunner(stdout: 'feat: add ai text\n');
      final service = CliAiTextGenerationService(
        gitBackend: git,
        processRunner: runner,
      );

      final result = await service.generate(
        const AiTextGenerationRequest(
          operation: AiTextGenerationOperation.commitMessage,
          workspacePath: '/repo',
          settings: AiTextGenerationSettings(agent: AiTextGenerationAgent.agy),
        ),
      );

      expect(result.text, 'feat: add ai text');
      expect(runner.executable, 'agy');
      expect(runner.arguments, containsAll(<String>['--print', '--sandbox']));
      expect(runner.arguments, contains('Gemini 3.5 Flash (Medium)'));
      expect(runner.stdinText, contains('feature/ai-text'));
      expect(runner.stdinClosed, isTrue);
    });

    test(
      'starts commit message agents with resolved command environment',
      () async {
        final git = FakeGitBackend()
          ..gitRepositoryStateResult = const GitRepositoryState(
            branch: 'feature/ai-text',
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
        final runner = _FakeProcessRunner(stdout: 'feat: add ai text\n');
        final service = CliAiTextGenerationService(
          gitBackend: git,
          processRunner: runner,
          commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
            value: <String, String>{'PATH': '/shell/bin:/usr/bin'},
          ),
        );

        await service.generate(
          const AiTextGenerationRequest(
            operation: AiTextGenerationOperation.commitMessage,
            workspacePath: '/repo',
            settings: AiTextGenerationSettings(
              agent: AiTextGenerationAgent.agy,
            ),
          ),
        );

        expect(runner.environment, containsPair('PATH', '/shell/bin:/usr/bin'));
      },
    );

    test('generates commit message with amp without archived flag', () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-text',
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
      final runner = _FakeProcessRunner(stdout: 'fix: update source control\n');
      final service = CliAiTextGenerationService(
        gitBackend: git,
        processRunner: runner,
      );

      await service.generate(
        const AiTextGenerationRequest(
          operation: AiTextGenerationOperation.commitMessage,
          workspacePath: '/repo',
          settings: AiTextGenerationSettings(agent: AiTextGenerationAgent.amp),
        ),
      );

      expect(runner.executable, 'amp');
      expect(runner.arguments, contains('--execute'));
      expect(runner.arguments, isNot(contains('--archive')));
    });

    test('generates commit message with opencode using stdin', () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-text',
        )
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/large.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
            ),
          ],
        )
        ..gitDiffResult = GitDiffResult(
          files: <GitDiffFile>[
            GitDiffFile(
              path: 'lib/large.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
              lines: <GitDiffLine>[
                GitDiffLine.addition(
                  '+${List<String>.filled(30000, 'x').join()}',
                ),
              ],
            ),
          ],
        );
      final runner = _FakeProcessRunner(stdout: 'feat: handle large diff\n');
      final service = CliAiTextGenerationService(
        gitBackend: git,
        processRunner: runner,
      );

      final result = await service.generate(
        const AiTextGenerationRequest(
          operation: AiTextGenerationOperation.commitMessage,
          workspacePath: '/repo',
          settings: AiTextGenerationSettings(
            agent: AiTextGenerationAgent.opencode,
          ),
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

    test('discovers dynamic models through the agent CLI', () async {
      final runner = _FakeProcessRunner(
        stdout: '''
Gemini 3.5 Flash (Medium)
Claude Sonnet 4.6 (Thinking)
''',
      );
      final service = CliAiTextModelDiscoveryService(processRunner: runner);

      final result = await service.discover(AiTextGenerationAgent.agy);

      expect(result.success, isTrue);
      expect(result.defaultModelId, 'Gemini 3.5 Flash (Medium)');
      expect(result.models.map((model) => model.id), <String>[
        'Gemini 3.5 Flash (Medium)',
        'Claude Sonnet 4.6 (Thinking)',
      ]);
      expect(runner.executable, 'agy');
      expect(runner.arguments, <String>['models']);
    });

    test(
      'discovers dynamic models with resolved command environment',
      () async {
        final runner = _FakeProcessRunner(
          stdout: 'Gemini 3.5 Flash (Medium)\n',
        );
        final service = CliAiTextModelDiscoveryService(
          processRunner: runner,
          commandEnvironmentResolver: const _FakeCommandEnvironmentResolver(
            value: <String, String>{'PATH': '/shell/bin:/usr/bin'},
          ),
        );

        await service.discover(AiTextGenerationAgent.agy);

        expect(runner.environment, containsPair('PATH', '/shell/bin:/usr/bin'));
      },
    );

    test('discovers pi models from stderr on successful exit', () async {
      final runner = _FakeProcessRunner(
        stdout: '',
        stderr: '''
provider        model                   context  max-out  thinking  images
github-copilot  gpt-5.4-mini            400K     128K     yes       yes
openai-codex    gpt-5.5                 272K     128K     yes       yes
''',
      );
      final service = CliAiTextModelDiscoveryService(processRunner: runner);

      final result = await service.discover(AiTextGenerationAgent.pi);

      expect(result.success, isTrue);
      expect(result.models.map((model) => model.id), <String>[
        'github-copilot/gpt-5.4-mini',
        'openai-codex/gpt-5.5',
      ]);
    });

    test('returns static models without spawning for static agents', () async {
      final runner = _FakeProcessRunner(stdout: 'unused');
      final service = CliAiTextModelDiscoveryService(processRunner: runner);

      final result = await service.discover(AiTextGenerationAgent.amp);

      expect(result.success, isTrue);
      expect(result.defaultModelId, 'smart');
      expect(runner.started, isFalse);
    });

    test(
      'falls back to static models when discovery returns no models',
      () async {
        final runner = _FakeProcessRunner(stdout: 'unparseable output');
        final service = CliAiTextModelDiscoveryService(processRunner: runner);

        final result = await service.discover(AiTextGenerationAgent.cursor);

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
      final service = CliAiTextModelDiscoveryService(processRunner: runner);

      final result = await service.discover(AiTextGenerationAgent.agy);

      expect(result.success, isFalse);
      expect(result.error, 'Antigravity model discovery failed: auth expired');
    });

    test('reports no staged changes before starting an agent', () async {
      final runner = _FakeProcessRunner(stdout: 'unused');
      final service = CliAiTextGenerationService(
        gitBackend: FakeGitBackend(),
        processRunner: runner,
      );

      await expectLater(
        service.generate(
          const AiTextGenerationRequest(
            operation: AiTextGenerationOperation.commitMessage,
            workspacePath: '/repo',
            settings: AiTextGenerationSettings(),
          ),
        ),
        throwsA(
          isA<AiTextGenerationException>().having(
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
          branch: 'feature/ai-text',
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
      final runner = _FakeProcessRunner(
        stdout: '',
        stderr: 'model is not available',
        exitCode: 1,
      );
      final service = CliAiTextGenerationService(
        gitBackend: git,
        processRunner: runner,
      );

      await expectLater(
        service.generate(
          const AiTextGenerationRequest(
            operation: AiTextGenerationOperation.commitMessage,
            workspacePath: '/repo',
            settings: AiTextGenerationSettings(
              agent: AiTextGenerationAgent.agy,
            ),
          ),
        ),
        throwsA(
          isA<AiTextGenerationException>().having(
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
            branch: 'feature/ai-text',
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
        final exitCode = Completer<int>();
        final runner = _FakeProcessRunner(
          stdout: '',
          exitCodeCompleter: exitCode,
        );
        final service = CliAiTextGenerationService(
          gitBackend: git,
          processRunner: runner,
        );

        final generation = service.generate(
          const AiTextGenerationRequest(
            operation: AiTextGenerationOperation.commitMessage,
            workspacePath: '/repo',
            settings: AiTextGenerationSettings(
              agent: AiTextGenerationAgent.agy,
            ),
          ),
        );
        await untilCalled(() => runner.started);

        service.cancel('/repo', AiTextGenerationOperation.commitMessage);

        await expectLater(
          generation,
          throwsA(isA<AiTextGenerationCanceledException>()),
        );
        expect(runner.killed, isTrue);
      },
    );

    test('keeps a canceled running lane reserved until process exit', () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-text',
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
      final exitCode = Completer<int>();
      final runner = _FakeProcessRunner(
        stdout: '',
        exitCodeCompleter: exitCode,
        completeExitOnKill: false,
      );
      final service = CliAiTextGenerationService(
        gitBackend: git,
        processRunner: runner,
      );

      final generation = service.generate(
        const AiTextGenerationRequest(
          operation: AiTextGenerationOperation.commitMessage,
          workspacePath: '/repo',
          settings: AiTextGenerationSettings(agent: AiTextGenerationAgent.agy),
        ),
      );
      await untilCalled(() => runner.started);

      service.cancel('/repo', AiTextGenerationOperation.commitMessage);

      await expectLater(
        service.generate(
          const AiTextGenerationRequest(
            operation: AiTextGenerationOperation.commitMessage,
            workspacePath: '/repo',
            settings: AiTextGenerationSettings(
              agent: AiTextGenerationAgent.agy,
            ),
          ),
        ),
        throwsA(
          isA<AiTextGenerationException>().having(
            (error) => error.message,
            'message',
            'Generation is already running.',
          ),
        ),
      );
      expect(runner.startCount, 1);

      exitCode.complete(143);
      await expectLater(
        generation,
        throwsA(isA<AiTextGenerationCanceledException>()),
      );
    });

    test('honors cancellation before the agent process starts', () async {
      final git = _DelayedDiffGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-text',
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
      final runner = _FakeProcessRunner(stdout: 'unused');
      final service = CliAiTextGenerationService(
        gitBackend: git,
        processRunner: runner,
      );

      final generation = service.generate(
        const AiTextGenerationRequest(
          operation: AiTextGenerationOperation.commitMessage,
          workspacePath: '/repo',
          settings: AiTextGenerationSettings(agent: AiTextGenerationAgent.agy),
        ),
      );
      await untilCalled(() => git.diffStarted);

      service.cancel('/repo', AiTextGenerationOperation.commitMessage);
      git.completeDiff();

      await expectLater(
        generation,
        throwsA(isA<AiTextGenerationCanceledException>()),
      );
      expect(runner.started, isFalse);
    });

    test('rejects oversized prompts for argv agents before starting', () async {
      final git = FakeGitBackend()
        ..gitRepositoryStateResult = const GitRepositoryState(
          branch: 'feature/ai-text',
        )
        ..gitStatusResult = const GitStatusResult(
          entries: <GitChangeEntry>[
            GitChangeEntry(
              path: 'lib/foo.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
            ),
          ],
        )
        ..gitDiffResult = GitDiffResult(
          files: <GitDiffFile>[
            GitDiffFile(
              path: 'lib/foo.dart',
              area: GitChangeArea.staged,
              status: GitChangeStatus.modified,
              lines: <GitDiffLine>[
                GitDiffLine.addition(
                  '+${List<String>.filled(30000, 'x').join()}',
                ),
              ],
            ),
          ],
        );
      final runner = _FakeProcessRunner(stdout: 'unused');
      final service = CliAiTextGenerationService(
        gitBackend: git,
        processRunner: runner,
      );

      await expectLater(
        service.generate(
          const AiTextGenerationRequest(
            operation: AiTextGenerationOperation.commitMessage,
            workspacePath: '/repo',
            settings: AiTextGenerationSettings(
              agent: AiTextGenerationAgent.copilot,
            ),
          ),
        ),
        throwsA(
          isA<AiTextGenerationException>().having(
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

class _FakeProcessRunner implements ProcessRunner {
  _FakeProcessRunner({
    required this.stdout,
    this.stderr = '',
    this.exitCode = 0,
    this.exitCodeCompleter,
    this.completeExitOnKill = true,
  });

  final String stdout;
  final String stderr;
  final int exitCode;
  final Completer<int>? exitCodeCompleter;
  final bool completeExitOnKill;
  bool started = false;
  int startCount = 0;
  bool stdinClosed = false;
  bool killed = false;
  String? executable;
  List<String> arguments = const <String>[];
  Map<String, String>? environment;
  final StringBuffer _stdin = StringBuffer();

  String get stdinText => _stdin.toString();

  @override
  Future<ProcessRunOutput> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return ProcessRunOutput(exitCode: exitCode, stdout: stdout, stderr: stderr);
  }

  @override
  Future<StartedProcess> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    started = true;
    startCount += 1;
    this.executable = executable;
    this.arguments = List<String>.from(arguments);
    this.environment = environment == null
        ? null
        : Map<String, String>.from(environment);
    return StartedProcess(
      stdinWrite: (data) => _stdin.write(utf8.decode(data)),
      stdinClose: () => stdinClosed = true,
      stdout: Stream<List<int>>.value(utf8.encode(stdout)),
      stderr: Stream<List<int>>.value(utf8.encode(stderr)),
      pid: 1,
      exitCode: exitCodeCompleter?.future ?? Future<int>.value(exitCode),
      kill: ([dynamic signal]) {
        killed = true;
        if (completeExitOnKill) {
          if (exitCodeCompleter case final completer?) {
            if (!completer.isCompleted) {
              completer.complete(143);
            }
          }
        }
        return true;
      },
    );
  }
}

class _FakeCommandEnvironmentResolver implements CommandEnvironmentResolver {
  const _FakeCommandEnvironmentResolver({
    this.value = const <String, String>{'PATH': '/usr/bin'},
  });

  final Map<String, String> value;

  @override
  Future<Map<String, String>> environment() async {
    return Map<String, String>.from(value);
  }
}

class _DelayedDiffGitBackend extends FakeGitBackend {
  final Completer<void> _diffGate = Completer<void>();
  bool diffStarted = false;

  @override
  Future<GitDiffResult> diff({
    required String path,
    required String filePath,
    required GitChangeArea area,
  }) async {
    diffStarted = true;
    await _diffGate.future;
    return super.diff(path: path, filePath: filePath, area: area);
  }

  void completeDiff() {
    if (!_diffGate.isCompleted) {
      _diffGate.complete();
    }
  }
}

Future<void> untilCalled(bool Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for call');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
