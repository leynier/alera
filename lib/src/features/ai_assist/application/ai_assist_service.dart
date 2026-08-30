import 'package:alera/src/features/ai_assist/application/ai_assist_agent_runner.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_errors.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_prompt.dart';
import 'package:alera/src/features/ai_assist/application/ai_assist_registry.dart';
import 'package:alera/src/features/ai_assist/domain/ai_assist_settings.dart';
import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/process/command_environment_resolver.dart';
import 'package:alera/src/shared/infra/process/process_runner.dart';

export 'ai_assist_errors.dart';

class AiAssistRequest {
  const AiAssistRequest({
    required this.operation,
    required this.workspacePath,
    required this.settings,
    this.baseBranch,
    this.headBranch,
  });

  final AiAssistOperation operation;
  final String workspacePath;
  final AiAssistSettings settings;

  /// Required when [operation] is [AiAssistOperation.pullRequestDetails].
  final String? baseBranch;

  /// Optional head branch hint for pull-request prompts.
  final String? headBranch;
}

class AiAssistResult {
  const AiAssistResult({required this.text, required this.agentLabel});

  final String text;
  final String agentLabel;
}

abstract interface class AiAssistService {
  Future<AiAssistResult> generate(AiAssistRequest request);

  void cancel(String workspacePath, AiAssistOperation operation);
}

class CliAiAssistService implements AiAssistService {
  CliAiAssistService({
    required this.gitBackend,
    required this.processRunner,
    CommandEnvironmentResolver? commandEnvironmentResolver,
    AiAssistAgentRunner? runner,
  }) : commandEnvironmentResolver =
           commandEnvironmentResolver ?? UserCommandEnvironmentResolver(),
       runner =
           runner ??
           CliAiAssistAgentRunner(
             processRunner: processRunner,
             commandEnvironmentResolver: commandEnvironmentResolver,
           );

  final GitBackend gitBackend;
  final ProcessRunner processRunner;
  final CommandEnvironmentResolver commandEnvironmentResolver;
  final AiAssistAgentRunner runner;
  final Set<String> _pending = <String>{};
  final Set<String> _canceled = <String>{};

  @override
  Future<AiAssistResult> generate(AiAssistRequest request) async {
    if (!request.settings.enabled) {
      throw const AiAssistException('AI Assist is disabled.');
    }
    final key = _laneKey(request.workspacePath, request.operation);
    if (_pending.contains(key)) {
      throw const AiAssistException('Generation is already running.');
    }
    _canceled.remove(key);
    _pending.add(key);

    try {
      final prompt = await _promptFor(request);
      if (_canceled.contains(key)) {
        throw const AiAssistCanceledException();
      }
      final agent = request.settings.agentFor(request.operation);
      final model = modelForAgent(
        agent,
        request.settings.modelForOperation(request.operation) ??
            defaultModelIdForAgent(agent, request.settings),
        extraModels: discoveredModelsForAgent(request.settings, agent),
      );
      final result = await runner.run(
        AiAssistAgentRunRequest(
          settings: request.settings,
          prompt: prompt,
          runId: key,
          workingDirectory: request.workspacePath,
          agent: agent,
          model: model.id,
          reasoning: request.settings.thinkingForOperation(
            request.operation,
            model.id,
          ),
          cleanOutput: request.operation == AiAssistOperation.commitMessage
              ? cleanGeneratedCommitMessage
              : cleanGeneratedText,
        ),
      );
      _pending.remove(key);
      if (_canceled.contains(key)) {
        throw const AiAssistCanceledException();
      }
      return AiAssistResult(text: result.text, agentLabel: result.agentLabel);
    } finally {
      _pending.remove(key);
      _canceled.remove(key);
    }
  }

  @override
  void cancel(String workspacePath, AiAssistOperation operation) {
    final key = _laneKey(workspacePath, operation);
    if (_pending.contains(key)) {
      _canceled.add(key);
      runner.cancel(key);
      return;
    }
    _canceled.add(key);
    runner.cancel(key);
  }

  Future<String> _promptFor(AiAssistRequest request) async {
    return switch (request.operation) {
      AiAssistOperation.commitMessage => buildCommitMessagePrompt(
        context: await _commitContext(request.workspacePath),
        customInstructions: promptInstructionsFor(
          request.settings,
          AiAssistOperation.commitMessage,
        ),
      ),
      AiAssistOperation.pullRequestDetails => buildPullRequestDetailsPrompt(
        context: await _pullRequestContext(request),
        customInstructions: promptInstructionsFor(
          request.settings,
          AiAssistOperation.pullRequestDetails,
        ),
      ),
      AiAssistOperation.branchName ||
      AiAssistOperation.readingDiff ||
      AiAssistOperation.workspaceIdentity ||
      AiAssistOperation.agentTitle ||
      AiAssistOperation.speechMessage => throw AiAssistException(
        '${request.operation.label} generation is not wired yet.',
      ),
    };
  }

  Future<AiAssistPullRequestContext> _pullRequestContext(
    AiAssistRequest request,
  ) async {
    final base = request.baseBranch?.trim() ?? '';
    if (base.isEmpty) {
      throw const AiAssistException(
        'Select a base branch before generating pull request details.',
      );
    }
    final range = await gitBackend.rangeContext(
      request.workspacePath,
      baseRef: base,
    );
    if (range.isEmpty) {
      throw const AiAssistException(
        'No commits or changes found against the base branch.',
      );
    }
    final head = request.headBranch?.trim().isNotEmpty == true
        ? request.headBranch!.trim()
        : range.headBranch;
    if (head != null && head == base) {
      throw const AiAssistException(
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
    return AiAssistPullRequestContext(
      baseBranch: base,
      headBranch: head,
      commitSummary: commitSummary,
      fileSummary: fileSummary,
      patch: range.patch,
    );
  }

  Future<AiAssistCommitContext> _commitContext(String workspacePath) async {
    final status = await gitBackend.status(workspacePath);
    final staged = status.entries
        .where((entry) => entry.area == GitChangeArea.staged)
        .toList(growable: false);
    if (staged.isEmpty) {
      throw const AiAssistException('No staged changes to summarize.');
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
    return AiAssistCommitContext(
      branch: repository.branch == 'HEAD' ? null : repository.branch,
      stagedSummary: summary,
      stagedPatch: patches.join('\n'),
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

  String _laneKey(String workspacePath, AiAssistOperation operation) {
    return '$workspacePath::${operation.key}';
  }
}
