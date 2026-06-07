import 'dart:async';

import 'package:alera/src/shared/infra/git/git_backend.dart';
import 'package:alera/src/shared/infra/git/git_diff_models.dart';
import 'package:alera/src/shared/infra/git/git_exception.dart';
import 'package:alera/src/shared/infra/git/git_providers.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'workspace_source_control_controller.g.dart';

class WorkspaceSourceControlState {
  const WorkspaceSourceControlState({
    required this.status,
    required this.repositoryState,
    required this.stashes,
    this.action,
  });

  final GitStatusResult status;
  final GitRepositoryState repositoryState;
  final List<GitStashEntry> stashes;
  final WorkspaceSourceControlAction? action;

  bool get isBusy => action != null;

  List<GitChangeEntry> get stagedEntries => status.entries
      .where((entry) => entry.area == GitChangeArea.staged)
      .toList(growable: false);

  bool get hasStagedChanges => stagedEntries.isNotEmpty;

  bool get hasChanges => status.entries.isNotEmpty;

  bool get hasUnstagedOrUntrackedChanges => status.entries.any(
    (entry) =>
        entry.area == GitChangeArea.unstaged ||
        entry.area == GitChangeArea.untracked,
  );

  bool get hasStashableChanges => status.entries.any(
    (entry) =>
        entry.area == GitChangeArea.staged ||
        entry.area == GitChangeArea.unstaged,
  );
}

enum WorkspaceSourceControlAction {
  refresh,
  stage,
  unstage,
  discard,
  commit,
  fetch,
  pull,
  push,
  sync,
  stash,
  stashPop,
}

@riverpod
class WorkspaceSourceControlController
    extends _$WorkspaceSourceControlController {
  @override
  Future<WorkspaceSourceControlState> build(String workspacePath) {
    return _load();
  }

  Future<void> refresh() =>
      _run(WorkspaceSourceControlAction.refresh, (_) async {});

  Future<void> stage(String? filePath) => _run(
    WorkspaceSourceControlAction.stage,
    (backend) => backend.stage(path: workspacePath, filePath: filePath),
  );

  Future<void> stageEntry(GitChangeEntry entry) =>
      _run(WorkspaceSourceControlAction.stage, (backend) async {
        for (final filePath in _actionPaths(entry)) {
          await backend.stage(path: workspacePath, filePath: filePath);
        }
      });

  Future<void> unstage(String? filePath) => _run(
    WorkspaceSourceControlAction.unstage,
    (backend) => backend.unstage(path: workspacePath, filePath: filePath),
  );

  Future<void> unstageEntry(GitChangeEntry entry) =>
      _run(WorkspaceSourceControlAction.unstage, (backend) async {
        for (final filePath in _actionPaths(entry)) {
          await backend.unstage(path: workspacePath, filePath: filePath);
        }
      });

  Future<void> discard(String? filePath) => _run(
    WorkspaceSourceControlAction.discard,
    (backend) => backend.discard(path: workspacePath, filePath: filePath),
  );

  Future<void> discardEntry(GitChangeEntry entry) =>
      _run(WorkspaceSourceControlAction.discard, (backend) async {
        for (final filePath in _actionPaths(entry)) {
          await backend.discard(path: workspacePath, filePath: filePath);
        }
      });

  Future<void> commit(String message) => _run(
    WorkspaceSourceControlAction.commit,
    (backend) => backend.commit(path: workspacePath, message: message.trim()),
  );

  Future<void> fetch() => _run(
    WorkspaceSourceControlAction.fetch,
    (backend) => backend.fetch(workspacePath),
  );

  Future<void> pull() => _run(
    WorkspaceSourceControlAction.pull,
    (backend) => backend.pull(workspacePath),
  );

  Future<void> push() => _run(
    WorkspaceSourceControlAction.push,
    (backend) => backend.push(workspacePath),
  );

  Future<void> sync() =>
      _run(WorkspaceSourceControlAction.sync, (backend) async {
        if (!(state.asData?.value.repositoryState.hasUpstream ?? false)) {
          throw const NoUpstreamException('set an upstream before syncing');
        }
        await backend.pull(workspacePath);
        await backend.push(workspacePath);
      });

  Future<void> stash() => _run(
    WorkspaceSourceControlAction.stash,
    (backend) => backend.stash(workspacePath),
  );

  Future<void> stashPop(int stashIndex) => _run(
    WorkspaceSourceControlAction.stashPop,
    (backend) => backend.stashPop(path: workspacePath, stashIndex: stashIndex),
  );

  Future<WorkspaceSourceControlState> _load() async {
    final backend = ref.read(gitBackendProvider);
    final results = await Future.wait<Object>([
      backend.status(workspacePath),
      backend.repositoryState(workspacePath),
      backend.listStashes(workspacePath),
    ]);
    return WorkspaceSourceControlState(
      status: results[0] as GitStatusResult,
      repositoryState: results[1] as GitRepositoryState,
      stashes: results[2] as List<GitStashEntry>,
    );
  }

  Future<void> _run(
    WorkspaceSourceControlAction action,
    Future<void> Function(GitBackend backend) operation,
  ) async {
    final previous = state.asData?.value;
    if (previous?.isBusy ?? false) {
      return;
    }
    if (previous != null) {
      state = AsyncData(
        WorkspaceSourceControlState(
          status: previous.status,
          repositoryState: previous.repositoryState,
          stashes: previous.stashes,
          action: action,
        ),
      );
    }
    try {
      await operation(ref.read(gitBackendProvider));
      state = AsyncData(await _load());
    } catch (error, stackTrace) {
      final recovered = await _recoverAfterFailure(previous);
      if (recovered != null) {
        state = AsyncData(recovered);
      } else {
        state = AsyncError(error, stackTrace);
      }
      rethrow;
    }
  }

  Future<WorkspaceSourceControlState?> _recoverAfterFailure(
    WorkspaceSourceControlState? previous,
  ) async {
    try {
      return await _load();
    } catch (_) {
      return previous;
    }
  }

  List<String> _actionPaths(GitChangeEntry entry) {
    final paths = <String>[];
    final oldPath = entry.oldPath;
    if (entry.status == GitChangeStatus.renamed &&
        oldPath != null &&
        oldPath != entry.path) {
      paths.add(oldPath);
    }
    paths.add(entry.path);
    return paths;
  }
}
