import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_prompt.dart';
import 'package:alera/src/features/ai_text_generation/application/ai_text_generation_registry.dart';
import 'package:alera/src/features/ai_text_generation/domain/ai_text_generation_settings.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';
import 'package:path/path.dart' as p;

part 'ai_text_generation_command_plan.dart';

const int maxArgvPromptBytes = 24000;

class AiTextGenerationException implements Exception {
  const AiTextGenerationException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AiTextGenerationCanceledException extends AiTextGenerationException {
  const AiTextGenerationCanceledException() : super('Generation canceled.');
}

class AiTextGenerationRequest {
  const AiTextGenerationRequest({
    required this.operation,
    required this.workspacePath,
    required this.settings,
    this.baseBranch,
    this.headBranch,
  });

  final AiTextGenerationOperation operation;
  final String workspacePath;
  final AiTextGenerationSettings settings;

  /// Required when [operation] is [AiTextGenerationOperation.pullRequestDetails].
  final String? baseBranch;

  /// Optional head branch hint for pull-request prompts.
  final String? headBranch;
}

class AiTextGenerationResult {
  const AiTextGenerationResult({required this.text, required this.agentLabel});

  final String text;
  final String agentLabel;
}

abstract interface class AiTextGenerationService {
  Future<AiTextGenerationResult> generate(AiTextGenerationRequest request);

  void cancel(String workspacePath, AiTextGenerationOperation operation);
}

class CliAiTextGenerationService implements AiTextGenerationService {
  CliAiTextGenerationService({
    required this.gitBackend,
    required this.processRunner,
    CommandEnvironmentResolver? commandEnvironmentResolver,
  }) : commandEnvironmentResolver =
           commandEnvironmentResolver ?? UserCommandEnvironmentResolver();

  final GitBackend gitBackend;
  final ProcessRunner processRunner;
  final CommandEnvironmentResolver commandEnvironmentResolver;
  final Map<String, StartedProcess> _running = <String, StartedProcess>{};
  final Set<String> _pending = <String>{};
  final Set<String> _canceled = <String>{};

  @override
  Future<AiTextGenerationResult> generate(
    AiTextGenerationRequest request,
  ) async {
    if (!request.settings.enabled) {
      throw const AiTextGenerationException('AI text generation is disabled.');
    }
    final key = _laneKey(request.workspacePath, request.operation);
    if (_pending.contains(key) || _running.containsKey(key)) {
      throw const AiTextGenerationException('Generation is already running.');
    }
    _canceled.remove(key);
    _pending.add(key);

    _AiTextCommandPlan? plan;
    try {
      final prompt = await _promptFor(request);
      if (_canceled.contains(key)) {
        throw const AiTextGenerationCanceledException();
      }
      final environment = await commandEnvironmentResolver.environment();
      plan = await _planCommand(request.settings, prompt, environment);
      if (_canceled.contains(key)) {
        throw const AiTextGenerationCanceledException();
      }
      final StartedProcess process;
      try {
        process = await processRunner.start(
          plan.binary,
          plan.args,
          workingDirectory: request.workspacePath,
          environment: <String, String>{
            ...environment,
            ...plan.environmentOverrides,
          },
        );
      } catch (_) {
        throw AiTextGenerationException(
          '${plan.label} could not be started. Check that ${plan.binary} is installed and on PATH.',
        );
      }
      if (_canceled.contains(key)) {
        process.kill();
        throw const AiTextGenerationCanceledException();
      }
      _pending.remove(key);
      _running[key] = process;
      if (plan.stdinPayload != null) {
        process.stdinWrite(utf8.encode(plan.stdinPayload!));
        process.stdinClose();
      }
      final output = await _collectProcess(process).timeout(
        Duration(seconds: request.settings.timeoutSeconds),
        onTimeout: () {
          process.kill();
          throw AiTextGenerationException(
            'Generation timed out after ${request.settings.timeoutSeconds}s.',
          );
        },
      );
      if (_canceled.contains(key)) {
        throw const AiTextGenerationCanceledException();
      }
      if (output.exitCode != 0) {
        final detail = _failureDetail(output.stdout, output.stderr);
        throw AiTextGenerationException(
          detail == null
              ? '${plan.label} failed. Check the agent CLI configuration and try again.'
              : '${plan.label} failed: $detail',
        );
      }
      final text = _cleanOutput(request.operation, output.stdout);
      if (text.trim().isEmpty) {
        throw AiTextGenerationException('${plan.label} returned no text.');
      }
      return AiTextGenerationResult(text: text, agentLabel: plan.label);
    } finally {
      _pending.remove(key);
      _running.remove(key);
      _canceled.remove(key);
      await plan?.dispose();
    }
  }

  @override
  void cancel(String workspacePath, AiTextGenerationOperation operation) {
    final key = _laneKey(workspacePath, operation);
    final process = _running[key];
    if (_pending.contains(key)) {
      _canceled.add(key);
      return;
    }
    if (process == null) {
      return;
    }
    _canceled.add(key);
    process.kill();
  }

  Future<String> _promptFor(AiTextGenerationRequest request) async {
    return switch (request.operation) {
      AiTextGenerationOperation.commitMessage => buildCommitMessagePrompt(
        context: await _commitContext(request.workspacePath),
        customInstructions: promptInstructionsFor(
          request.settings,
          AiTextGenerationOperation.commitMessage,
        ),
      ),
      AiTextGenerationOperation.pullRequestDetails =>
        buildPullRequestDetailsPrompt(
          context: await _pullRequestContext(request),
          customInstructions: promptInstructionsFor(
            request.settings,
            AiTextGenerationOperation.pullRequestDetails,
          ),
        ),
      AiTextGenerationOperation.branchName => throw AiTextGenerationException(
        '${request.operation.label} generation is not wired yet.',
      ),
    };
  }

  Future<AiTextPullRequestContext> _pullRequestContext(
    AiTextGenerationRequest request,
  ) async {
    final base = request.baseBranch?.trim() ?? '';
    if (base.isEmpty) {
      throw const AiTextGenerationException(
        'Select a base branch before generating pull request details.',
      );
    }
    final range = await gitBackend.rangeContext(
      request.workspacePath,
      baseRef: base,
    );
    if (range.isEmpty) {
      throw const AiTextGenerationException(
        'No commits or changes found against the base branch.',
      );
    }
    final head = request.headBranch?.trim().isNotEmpty == true
        ? request.headBranch!.trim()
        : range.headBranch;
    if (head != null && head == base) {
      throw const AiTextGenerationException(
        'Head branch is the same as the base branch.',
      );
    }
    final commitSummary = range.commits.isEmpty
        ? '(no commits in range)'
        : range.commits
              .map((commit) {
                final short = commit.oid.length > 7
                    ? commit.oid.substring(0, 7)
                    : commit.oid;
                return '- $short ${commit.subject}';
              })
              .join('\n');
    final fileSummary = range.files.isEmpty
        ? '(no file list)'
        : range.files
              .map((file) {
                final counts = <String>[
                  if (file.added != null) '+${file.added}',
                  if (file.removed != null) '-${file.removed}',
                ].join(' ');
                final badge = file.status.badge;
                return counts.isEmpty
                    ? '- $badge ${file.path}'
                    : '- $badge ${file.path} ($counts)';
              })
              .join('\n');
    return AiTextPullRequestContext(
      baseBranch: base,
      headBranch: head,
      commitSummary: commitSummary,
      fileSummary: fileSummary,
      patch: range.patch,
    );
  }

  Future<AiTextCommitContext> _commitContext(String workspacePath) async {
    final status = await gitBackend.status(workspacePath);
    final staged = status.entries
        .where((entry) => entry.area == GitChangeArea.staged)
        .toList(growable: false);
    if (staged.isEmpty) {
      throw const AiTextGenerationException('No staged changes to summarize.');
    }
    final repository = await gitBackend.repositoryState(workspacePath);
    final summary = staged
        .map((entry) {
          final counts = <String>[
            if (entry.added != null) '+${entry.added}',
            if (entry.removed != null) '-${entry.removed}',
          ].join(' ');
          final prefix = entry.oldPath == null
              ? entry.path
              : '${entry.oldPath} -> ${entry.path}';
          return counts.isEmpty ? '- $prefix' : '- $prefix ($counts)';
        })
        .join('\n');
    final patches = <String>[];
    for (final entry in staged) {
      final diff = await gitBackend.diff(
        path: workspacePath,
        filePath: entry.path,
        area: GitChangeArea.staged,
      );
      patches.add(_diffToPatch(diff));
    }
    return AiTextCommitContext(
      branch: repository.branch == 'HEAD' ? null : repository.branch,
      stagedSummary: summary,
      stagedPatch: patches.join('\n'),
    );
  }

  Future<_AiTextCommandPlan> _planCommand(
    AiTextGenerationSettings settings,
    String prompt,
    Map<String, String> environment,
  ) async {
    if (settings.agent == AiTextGenerationAgent.custom) {
      return _planCustomCommand(settings.customCommand, prompt);
    }
    final spec = aiTextAgentSpecs[settings.agent];
    if (spec == null) {
      throw AiTextGenerationException(
        '${settings.agent.label} does not support AI text generation.',
      );
    }
    final model = modelForAgent(
      settings.agent,
      settings.modelFor(settings.agent) ??
          defaultModelIdForAgent(settings.agent, settings),
      extraModels: discoveredModelsForAgent(settings, settings.agent),
    );
    final thinking =
        settings.thinkingForModel(model.id) ?? model.defaultThinkingLevel;
    if (spec.promptDelivery == AiPromptDelivery.argv &&
        utf8.encode(prompt).length > maxArgvPromptBytes) {
      throw AiTextGenerationException(
        '${spec.label} cannot receive large prompts safely. Choose an agent that supports stdin prompts or reduce the staged diff.',
      );
    }
    Directory? promptDirectory;
    final environmentOverrides = <String, String>{};
    var deliveredPrompt = '';
    if (spec.promptDelivery == AiPromptDelivery.argv) {
      deliveredPrompt = prompt;
    } else if (spec.promptDelivery == AiPromptDelivery.promptFile) {
      promptDirectory = await Directory.systemTemp.createTemp('alera-ai-text-');
      try {
        final promptFile = File(
          '${promptDirectory.path}${Platform.pathSeparator}prompt.txt',
        );
        await promptFile.writeAsString(prompt, flush: true);
        deliveredPrompt = promptFile.path;
        if (settings.agent == AiTextGenerationAgent.grok) {
          final grokHome = Directory(p.join(promptDirectory.path, 'grok-home'));
          await grokHome.create();
          await _copyGrokRuntimeConfiguration(grokHome, environment);
          environmentOverrides['GROK_HOME'] = grokHome.path;
        }
      } catch (_) {
        try {
          await promptDirectory.delete(recursive: true);
        } catch (_) {}
        rethrow;
      }
    }
    return _AiTextCommandPlan(
      binary: spec.binary,
      args: spec.buildArgs(
        prompt: deliveredPrompt,
        model: model.id,
        thinkingLevel: thinking,
        timeoutSeconds: settings.timeoutSeconds,
      ),
      stdinPayload: spec.promptDelivery == AiPromptDelivery.stdin
          ? prompt
          : null,
      label: spec.label,
      promptDirectory: promptDirectory,
      environmentOverrides: environmentOverrides,
    );
  }

  Future<void> _copyGrokRuntimeConfiguration(
    Directory isolatedHome,
    Map<String, String> environment,
  ) async {
    final configuredHome = environment['GROK_HOME']?.trim();
    final userHome = (environment['HOME'] ?? environment['USERPROFILE'])
        ?.trim();
    final sourceHome = configuredHome != null && configuredHome.isNotEmpty
        ? configuredHome
        : userHome != null && userHome.isNotEmpty
        ? p.join(userHome, '.grok')
        : null;
    if (sourceHome == null) {
      return;
    }
    for (final fileName in const <String>[
      'auth.json',
      'config.toml',
      'managed_config.toml',
      'requirements.toml',
    ]) {
      final source = File(p.join(sourceHome, fileName));
      if (await source.exists()) {
        await source.copy(p.join(isolatedHome.path, fileName));
      }
    }
  }

  _AiTextCommandPlan _planCustomCommand(String template, String prompt) {
    final tokens = _tokenizeCommandTemplate(template);
    if (tokens.isEmpty) {
      throw const AiTextGenerationException('Custom command is empty.');
    }
    final usesPlaceholder = tokens.any((token) => token.contains('{prompt}'));
    final substituted = tokens
        .map((token) => token.replaceAll('{prompt}', prompt))
        .toList(growable: false);
    return _AiTextCommandPlan(
      binary: substituted.first,
      args: substituted.skip(1).toList(growable: false),
      stdinPayload: usesPlaceholder ? null : prompt,
      label: substituted.first,
    );
  }

  List<String> _tokenizeCommandTemplate(String template) {
    final matches = RegExp(
      r'''"([^"]*)"|'([^']*)'|(\S+)''',
    ).allMatches(template);
    return matches
        .map((match) => match.group(1) ?? match.group(2) ?? match.group(3)!)
        .toList(growable: false);
  }

  Future<ProcessRunOutput> _collectProcess(StartedProcess process) async {
    final stdout = StringBuffer();
    final stderr = StringBuffer();
    final stdoutDone = utf8.decoder.bind(process.stdout).forEach(stdout.write);
    final stderrDone = utf8.decoder.bind(process.stderr).forEach(stderr.write);
    final exitCode = await process.exitCode;
    await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    return ProcessRunOutput(
      exitCode: exitCode,
      stdout: stdout.toString(),
      stderr: stderr.toString(),
    );
  }

  String _diffToPatch(GitDiffResult diff) {
    return diff.files
        .map((file) {
          final header = <String>[
            'diff --git a/${file.oldPath ?? file.path} b/${file.path}',
            if (file.isBinary) 'Binary file changed',
            if (file.isLarge) 'Large file preview truncated',
          ];
          final lines = file.lines.map((line) => line.text);
          return <String>[...header, ...lines].join('\n');
        })
        .join('\n');
  }

  String _cleanOutput(AiTextGenerationOperation operation, String stdout) {
    return switch (operation) {
      AiTextGenerationOperation.commitMessage => cleanGeneratedCommitMessage(
        stdout,
      ),
      AiTextGenerationOperation.pullRequestDetails ||
      AiTextGenerationOperation.branchName => cleanGeneratedText(stdout),
    };
  }

  String? _failureDetail(String stdout, String stderr) {
    final combined = '$stdout\n$stderr'
        .replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '')
        .trim();
    if (combined.isEmpty) {
      return null;
    }
    final lines = combined
        .split(RegExp(r'\r?\n'))
        .where((line) {
          return line.trim().isNotEmpty;
        })
        .toList(growable: false);
    final detail = lines.isEmpty ? combined : lines.last.trim();
    return detail.length > 240
        ? '${detail.substring(0, 240).trimRight()}...'
        : detail;
  }

  String _laneKey(String workspacePath, AiTextGenerationOperation operation) {
    return '$workspacePath::${operation.key}';
  }
}
