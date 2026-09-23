part of 'workspace_pull_request_controller.dart';

mixin _WorkspacePullRequestShipActions on _$WorkspacePullRequestController {
  static const int _maxBranchCandidates = 100;
  static const int _maxBranchSlugLength = 48;

  WorkspacePullRequestController get _shipController =>
      this as WorkspacePullRequestController;

  /// Commits staged changes with an AI-generated message and creates a pull
  /// request. When [scope] is [PullRequestShipScope.all], all working-tree
  /// changes are staged first. A checkout on a shared or selected base branch
  /// is moved first. Existing commits on a feature branch, or unpushed commits
  /// on the base branch, can be shipped without a new working-tree change.
  Future<CreateReviewResult> ship({
    required String baseBranch,
    required bool draft,
    required AiAssistSettings settings,
    required PullRequestShipScope scope,
  }) async {
    final controller = _shipController;
    final previous = state.value ?? const WorkspacePullRequestState();
    if (previous.isBusy) {
      return const CreateReviewFailure(
        code: .blocked,
        message: 'Another pull request action is already running.',
      );
    }
    if (!previous.supportsCreation) {
      return _blockedShip(
        'A new pull request cannot be created from the current panel state.',
      );
    }
    if (!settings.enabled) {
      return _blockedShip('Enable AI Assist before shipping changes.');
    }
    final normalizedBase = baseBranch.trim();
    if (normalizedBase.isEmpty) {
      return _blockedShip('Select a base branch before shipping.');
    }

    controller._pollTimer?.cancel();
    state = AsyncData(previous.copyWith(action: .ship, clearError: true));
    var changesCommitted = false;
    try {
      final backend = controller._gitBackend;
      final repoPath = controller.scope.repoPath;
      final status = await backend.status(repoPath);
      var headBranch = await backend.currentBranch(repoPath);
      if (headBranch.isEmpty || headBranch == 'HEAD') {
        throw const _ActionError('Check out a branch before shipping.');
      }

      final hasStaged = status.entries.any((entry) => entry.area == .staged);
      final hasLeftoverWorkingTree = status.entries.any(
        (entry) => entry.area != .staged,
      );
      final needsCommit = scope == PullRequestShipScope.all
          ? status.entries.isNotEmpty
          : hasStaged;
      if (scope == PullRequestShipScope.staged && hasLeftoverWorkingTree) {
        throw const _ActionError('Stage at least one change before shipping.');
      }

      final sourceBranch = headBranch;
      final sourceHeadRef = _localHeadRef(sourceBranch);
      final moveOffBase = _requiresShipBranch(headBranch, normalizedBase);
      var unpushedOnBase = false;
      String? trackingRef;
      String? sourceOid;
      String? existingCommitMessage;
      if (moveOffBase) {
        await backend.fetch(repoPath);
        final originTrackingRef = _originTrackingRef(sourceBranch);
        trackingRef = originTrackingRef;
        final trackingRange = await _rangeAheadOf(
          backend: backend,
          repoPath: repoPath,
          baseRef: originTrackingRef,
          headRef: sourceHeadRef,
          missingRefMessage:
              'Could not find $originTrackingRef after fetch. Fetch the remote tracking branch before shipping.',
        );
        unpushedOnBase = trackingRange.commits.isNotEmpty;
        sourceOid = trackingRange.headOid;
        if (unpushedOnBase) {
          existingCommitMessage = _commitMessageFromRange(trackingRange);
        }
      } else if (!needsCommit) {
        final range = await backend.rangeContext(
          repoPath,
          baseRef: normalizedBase,
          headRef: sourceHeadRef,
        );
        if (range.commits.isEmpty) {
          throw const _ActionError('No changes to ship.');
        }
        existingCommitMessage = _commitMessageFromRange(range);
      }

      if (!needsCommit && moveOffBase && !unpushedOnBase) {
        throw const _ActionError('No changes to ship.');
      }

      if (needsCommit && scope == PullRequestShipScope.all) {
        await backend.stage(path: repoPath);
      }

      final aiAssist = ref.read(aiAssistServiceProvider);
      var commitMessage = existingCommitMessage ?? '';
      if (needsCommit) {
        final generatedCommit = await aiAssist.generate(
          AiAssistRequest(
            operation: .commitMessage,
            workspacePath: repoPath,
            settings: settings,
          ),
        );
        commitMessage = generatedCommit.text.trim();
        if (commitMessage.isEmpty) {
          throw const _ActionError(
            'AI Assist returned an empty commit message.',
          );
        }
      } else if (commitMessage.isEmpty) {
        commitMessage = 'Update Project';
      }

      if (moveOffBase) {
        headBranch = await _availableShipBranchName(
          backend: backend,
          repoPath: repoPath,
          commitMessage: commitMessage,
        );
        await backend.createAndCheckoutBranch(
          path: repoPath,
          branch: headBranch,
          expectedHead: sourceBranch,
          expectedOid: sourceOid,
        );
        if (unpushedOnBase && trackingRef != null) {
          await backend.resetBranchToRef(
            path: repoPath,
            branch: sourceBranch,
            targetRef: trackingRef,
            expectedOid: sourceOid,
          );
        }
      }

      if (needsCommit) {
        await backend.commit(path: repoPath, message: commitMessage);
        changesCommitted = true;
      }
      final details = await _reviewDetails(
        aiAssist: aiAssist,
        settings: settings,
        repoPath: repoPath,
        baseBranch: normalizedBase,
        headBranch: headBranch,
        commitMessage: commitMessage,
      );
      final identity = previous.identity!;
      final result = await controller._createReview(
        CreateReviewInput(
          provider: identity.provider,
          title: details.title,
          baseBranch: normalizedBase,
          headBranch: headBranch,
          body: details.body,
          draft: draft,
        ),
        action: .ship,
      );
      if (result is CreateReviewFailure) {
        return await _finishShipFailure(
          previous: previous,
          code: result.code,
          message: _shipFailureMessage(
            result.message,
            changesCommitted: changesCommitted,
          ),
        );
      }
      return result;
    } on _ActionError catch (error) {
      return _finishShipFailure(
        previous: previous,
        code: .blocked,
        message: _shipFailureMessage(
          error.message,
          changesCommitted: changesCommitted,
        ),
      );
    } on AiAssistException catch (error) {
      return _finishShipFailure(
        previous: previous,
        code: .blocked,
        message: _shipFailureMessage(
          error.message,
          changesCommitted: changesCommitted,
        ),
      );
    } on GitException catch (error) {
      return _finishShipFailure(
        previous: previous,
        code: .unknown,
        message: _shipFailureMessage(
          error.context,
          changesCommitted: changesCommitted,
        ),
      );
    } catch (error) {
      return _finishShipFailure(
        previous: previous,
        code: .unknown,
        message: _shipFailureMessage(
          error.toString(),
          changesCommitted: changesCommitted,
        ),
      );
    }
  }

  CreateReviewFailure _blockedShip(String message) {
    _shipController._applyActionOutcome(failureMessage: message);
    return CreateReviewFailure(code: .blocked, message: message);
  }

  String _shipFailureMessage(
    String message, {
    required bool changesCommitted,
  }) => changesCommitted ? _afterCommitFailure(message) : message;

  String _afterCommitFailure(String message) =>
      'The changes were committed, but Ship could not finish: $message';

  Future<CreateReviewFailure> _finishShipFailure({
    required WorkspacePullRequestState previous,
    required CreateReviewErrorCode code,
    required String message,
  }) async {
    final controller = _shipController;
    await controller._recordActionFailure(
      scope: controller.scope,
      previous: previous,
      message: message,
      reload: true,
    );
    controller._schedulePoll(controller.scope);
    return CreateReviewFailure(code: code, message: message);
  }

  bool _requiresShipBranch(String headBranch, String baseBranch) =>
      headBranch == baseBranch ||
      headBranch == 'main' ||
      headBranch == 'master';

  Future<String> _availableShipBranchName({
    required GitBackend backend,
    required String repoPath,
    required String commitMessage,
  }) async {
    final base = _shipBranchBase(commitMessage);
    for (var index = 1; index <= _maxBranchCandidates; index += 1) {
      final candidate = index == 1 ? base : '$base-$index';
      if (!await backend.isValidBranchName(candidate)) {
        continue;
      }
      if (!await backend.branchExists(repoPath, candidate)) {
        return candidate;
      }
    }
    throw const _ActionError(
      'Could not find an available branch name for the staged changes.',
    );
  }

  String _originTrackingRef(String branch) => 'refs/remotes/origin/$branch';

  String _localHeadRef(String branch) => 'refs/heads/$branch';

  Future<GitRangeContext> _rangeAheadOf({
    required GitBackend backend,
    required String repoPath,
    required String baseRef,
    required String headRef,
    required String missingRefMessage,
  }) async {
    try {
      return await backend.rangeContext(
        repoPath,
        baseRef: baseRef,
        headRef: headRef,
      );
    } on BranchNotFoundException {
      throw _ActionError(missingRefMessage);
    }
  }

  String? _commitMessageFromRange(GitRangeContext range) {
    for (final commit in range.commits) {
      final message = commit.message.trim();
      if (message.isNotEmpty) {
        return message;
      }
      final subject = commit.subject.trim();
      if (subject.isNotEmpty) {
        return subject;
      }
    }
    return null;
  }

  String _shipBranchBase(String commitMessage) {
    final subject = commitMessage
        .split('\n')
        .first
        .trim()
        .replaceFirst(RegExp(r'^[a-zA-Z]+(?:\([^)]+\))?!?:\s*'), '');
    var slug = subject
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty) {
      slug = 'changes';
    }
    if (slug.length > _maxBranchSlugLength) {
      slug = slug
          .substring(0, _maxBranchSlugLength)
          .replaceFirst(RegExp(r'-+$'), '');
    }
    return 'ship/$slug';
  }

  Future<GeneratedPullRequestDetails> _reviewDetails({
    required AiAssistService aiAssist,
    required AiAssistSettings settings,
    required String repoPath,
    required String baseBranch,
    required String headBranch,
    required String commitMessage,
  }) async {
    try {
      final generated = await aiAssist.generate(
        AiAssistRequest(
          operation: .pullRequestDetails,
          workspacePath: repoPath,
          settings: settings,
          baseBranch: baseBranch,
          headBranch: headBranch,
        ),
      );
      if (generated.text.trim().isEmpty) {
        return parseGeneratedPullRequestDetails(commitMessage);
      }
      return parseGeneratedPullRequestDetails(generated.text);
    } on Object {
      // The AI-generated commit already gives us safe deterministic PR text,
      // so optional PR-detail generation must never strand a completed commit.
      return parseGeneratedPullRequestDetails(commitMessage);
    }
  }
}
