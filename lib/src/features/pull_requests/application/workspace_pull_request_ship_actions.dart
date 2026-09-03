part of 'workspace_pull_request_controller.dart';

mixin _WorkspacePullRequestShipActions on _$WorkspacePullRequestController {
  static const int _maxBranchCandidates = 100;
  static const int _maxBranchSlugLength = 48;

  WorkspacePullRequestController get _shipController =>
      this as WorkspacePullRequestController;

  /// Commits staged changes with an AI-generated message and creates a pull
  /// request. When [scope] is [PullRequestShipScope.all], all working-tree
  /// changes are staged first. A checkout on a shared or selected base branch
  /// is moved first.
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
      return _blockedShip('Enable AI Assist before shipping staged changes.');
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
      final status = await backend.status(controller.scope.repoPath);
      if (scope == PullRequestShipScope.all) {
        if (status.entries.isEmpty) {
          throw const _ActionError('No changes to ship.');
        }
        await backend.stage(path: controller.scope.repoPath);
      } else if (!status.entries.any((entry) => entry.area == .staged)) {
        throw const _ActionError('Stage at least one change before shipping.');
      }

      var headBranch = await backend.currentBranch(controller.scope.repoPath);
      if (headBranch.isEmpty || headBranch == 'HEAD') {
        throw const _ActionError('Check out a branch before shipping.');
      }

      final aiAssist = ref.read(aiAssistServiceProvider);
      final generatedCommit = await aiAssist.generate(
        AiAssistRequest(
          operation: .commitMessage,
          workspacePath: controller.scope.repoPath,
          settings: settings,
        ),
      );
      final commitMessage = generatedCommit.text.trim();
      if (commitMessage.isEmpty) {
        throw const _ActionError('AI Assist returned an empty commit message.');
      }

      if (_requiresShipBranch(headBranch, normalizedBase)) {
        headBranch = await _availableShipBranchName(
          backend: backend,
          repoPath: controller.scope.repoPath,
          commitMessage: commitMessage,
        );
        await backend.createAndCheckoutBranch(
          path: controller.scope.repoPath,
          branch: headBranch,
        );
      }

      await backend.commit(
        path: controller.scope.repoPath,
        message: commitMessage,
      );
      changesCommitted = true;
      final details = await _reviewDetails(
        aiAssist: aiAssist,
        settings: settings,
        repoPath: controller.scope.repoPath,
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
          message: _afterCommitFailure(result.message),
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
      'The staged changes were committed, but Ship could not finish: $message';

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
