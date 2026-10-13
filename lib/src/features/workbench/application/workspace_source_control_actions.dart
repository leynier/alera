part of 'workspace_source_control_controller.dart';

mixin _WorkspaceSourceControlActions on _$WorkspaceSourceControlController {
  Future<void> runReviewedAction(
    Future<void> Function(GitBackend backend) operation,
  ) async {
    if (state.asData?.value.isBusy ?? false) {
      throw const GitConflictException(
        'Another Git action is already running.',
      );
    }
    await _run(.commitPush, operation);
  }

  Future<void> refresh() => _run(.refresh, (_) async {});

  Future<void> stage(String? filePath) => _run(
    .stage,
    (backend) => backend.stage(path: workspacePath, filePath: filePath),
  );

  Future<void> stageArea(GitChangeArea area, {String? filePath}) => _run(
    .stage,
    (backend) =>
        backend.stageArea(path: workspacePath, area: area, filePath: filePath),
  );

  Future<void> stageEntry(GitChangeEntry entry) {
    if (!entry.canStageFromParent) {
      return Future<void>.value();
    }
    return _run(.stage, (backend) async {
      for (final filePath in _actionPaths(entry)) {
        await backend.stage(path: workspacePath, filePath: filePath);
      }
    });
  }

  Future<void> unstage(String? filePath) => _run(
    .unstage,
    (backend) => backend.unstage(path: workspacePath, filePath: filePath),
  );

  Future<void> unstageArea(GitChangeArea area, {String? filePath}) => _run(
    .unstage,
    (backend) => backend.unstageArea(
      path: workspacePath,
      area: area,
      filePath: filePath,
    ),
  );

  Future<void> unstageEntry(GitChangeEntry entry) {
    if (!entry.canUnstageFromParent) {
      return Future<void>.value();
    }
    return _run(.unstage, (backend) async {
      for (final filePath in _actionPaths(entry)) {
        await backend.unstage(path: workspacePath, filePath: filePath);
      }
    });
  }

  Future<void> discard(String? filePath) => _run(
    .discard,
    (backend) => backend.discard(path: workspacePath, filePath: filePath),
  );

  Future<void> discardArea(GitChangeArea area, {String? filePath}) => _run(
    .discard,
    (backend) => backend.discardArea(
      path: workspacePath,
      area: area,
      filePath: filePath,
    ),
  );

  Future<void> discardEntry(GitChangeEntry entry) {
    if (!entry.canDiscardFromParent) {
      return Future<void>.value();
    }
    return _run(.discard, (backend) async {
      for (final filePath in _actionPaths(entry)) {
        await backend.discard(path: workspacePath, filePath: filePath);
      }
    });
  }

  Future<void> commit(String message) => _run(
    .commit,
    (backend) => backend.commit(path: workspacePath, message: message.trim()),
  );

  Future<void> commitAndPush(String message) =>
      _run(.commitPush, (backend) async {
        await backend.commit(path: workspacePath, message: message.trim());
        await backend.push(workspacePath);
      });

  Future<void> commitAndSync(String message) =>
      _run(.commitSync, (backend) async {
        await backend.commit(path: workspacePath, message: message.trim());
        if (!(state.asData?.value.repositoryState.hasUpstream ?? false)) {
          throw const NoUpstreamException('set an upstream before syncing');
        }
        await backend.pull(workspacePath);
        await backend.push(workspacePath);
      });

  Future<void> amendCommit(String message) => _run(
    .amend,
    (backend) =>
        backend.amendCommit(path: workspacePath, message: message.trim()),
  );

  Future<void> fetch() =>
      _run(.fetch, (backend) => backend.fetch(workspacePath));

  Future<void> pull() => _run(.pull, (backend) => backend.pull(workspacePath));

  Future<void> push() => _run(.push, (backend) => backend.push(workspacePath));

  Future<void> sync() => _run(.sync, (backend) async {
    if (!(state.asData?.value.repositoryState.hasUpstream ?? false)) {
      throw const NoUpstreamException('set an upstream before syncing');
    }
    await backend.pull(workspacePath);
    await backend.push(workspacePath);
  });

  Future<void> stash() =>
      _run(.stash, (backend) => backend.stash(workspacePath));

  Future<void> stashPop(int stashIndex) => _run(
    .stashPop,
    (backend) => backend.stashPop(path: workspacePath, stashIndex: stashIndex),
  );

  Future<String> checkoutBranch(String branch) async {
    await _run(
      .checkout,
      (backend) => backend.checkoutBranch(path: workspacePath, branch: branch),
    );
    return state.requireValue.repositoryState.branch;
  }

  Future<void> createAndCheckoutBranch(String branch) => _run(
    .createBranch,
    (backend) =>
        backend.createAndCheckoutBranch(path: workspacePath, branch: branch),
  );

  Future<void> _run(
    WorkspaceSourceControlAction action,
    Future<void> Function(GitBackend backend) operation,
  );
  List<String> _actionPaths(GitChangeEntry entry);
}
